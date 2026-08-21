# SPDX-FileCopyrightText: 2026 ash_r2ml contributors <https://github.com/seanchatmangpt/ash_r2ml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2ml.Compilation do
  @moduledoc "Evidence-bounded result of ontology-first semantic compilation."

  defstruct [
    :status,
    :standing,
    :ir,
    :ash_source,
    :postgres_ddl,
    :r2rml,
    :shacl,
    :receipt,
    refusals: []
  ]
end

defmodule AshR2ml.CompilationReceipt do
  @moduledoc "Identity and standing record for one deterministic semantic compilation."

  defstruct [
    :status,
    :standing,
    :ontology_hash,
    :profile_hash,
    :shacl_input_hash,
    :ir_sha256,
    :ash_sha256,
    :postgres_sha256,
    :r2rml_sha256,
    :shacl_sha256,
    :query_parity,
    :neo4j_postgres_parity,
    classes_admitted: 0,
    attributes_admitted: 0,
    relationships_admitted: 0,
    actions_admitted: 0,
    policies_admitted: 0,
    storage_candidates: %{},
    selected_storage: %{},
    executed: [],
    verified: [],
    blocked: [],
    refusals: []
  ]
end

defmodule AshR2ml.Compiler do
  @moduledoc """
  Ontology-first compiler for the admitted closed operational profile.

  Pipeline:

      ontology/profile/SHACL-normalized input
          -> Admission
          -> SemanticIR
          -> Ash + PostgreSQL + R2RML + SHACL
          -> CompilationReceipt

  This is CONSTRUCT only. It neither applies migrations nor starts an OBDA
  service, and therefore cannot grant cutover standing by itself.
  """

  alias AshR2ml.{Admission, Compilation, CompilationReceipt, Refusal, SemanticIR}

  @spec explore(map()) :: {:ok, SemanticIR.t()} | {:error, [Refusal.t()]}
  def explore(profile), do: Admission.admit(profile)

  @spec compile(map()) :: {:ok, Compilation.t()} | {:error, Compilation.t()}
  def compile(profile) do
    case Admission.admit(profile) do
      {:error, refusals} ->
        {:error,
         %Compilation{
           status: :REFUSED,
           standing: :no_projection,
           refusals: refusals,
           receipt: refusal_receipt(refusals)
         }}

      {:ok, ir} ->
        case projection_refusals(ir) do
          [] -> render_all(ir)
          refusals ->
            {:error,
             %Compilation{
               status: :REFUSED,
               standing: :semantic_ir_only,
               ir: ir,
               refusals: refusals,
               receipt: refusal_receipt(refusals, ir)
             }}
        end
    end
  end

  @doc "Cutover is impossible from a compile receipt alone; parity witnesses must be attached explicitly."
  def cutover_ready?(%CompilationReceipt{
        query_parity: :VERIFIED,
        neo4j_postgres_parity: :VERIFIED,
        blocked: []
      }),
      do: true

  def cutover_ready?(_), do: false

  @doc """
  Upgrade a compilation receipt with an externally observed parity witness.

  The witness is data only; this function never executes SQL, SPARQL, or Cypher.
  It therefore requires explicit `verified?: true` from the verifier that performed
  the comparison and preserves the witness identity in the receipt's verified set.
  """
  def attach_parity_witness(%CompilationReceipt{} = receipt, kind, witness)
      when kind in [:sparql_sql, :neo4j_postgres] and is_map(witness) do
    verified? = Map.get(witness, :verified?, Map.get(witness, "verified?", false))
    witness_id = Map.get(witness, :receipt_sha256, Map.get(witness, "receipt_sha256"))

    if verified? and is_binary(witness_id) and witness_id != "" do
      receipt =
        case kind do
          :sparql_sql -> %{receipt | query_parity: :VERIFIED}
          :neo4j_postgres -> %{receipt | neo4j_postgres_parity: :VERIFIED}
        end

      blocked =
        case kind do
          :sparql_sql -> List.delete(receipt.blocked, :sparql_sql_behavioral_parity)
          :neo4j_postgres -> List.delete(receipt.blocked, :neo4j_postgres_semantic_parity)
        end

      %{receipt | blocked: blocked, verified: Enum.uniq([{:parity_witness, kind, witness_id} | receipt.verified])}
    else
      refusal =
        Refusal.new(
          :REFUSED_UNPROVEN_EQUIVALENCE,
          kind,
          "parity witness must be observed, verified, and carry a stable receipt_sha256",
          %{witness: witness}
        )

      %{receipt | refusals: [refusal | receipt.refusals]}
    end
  end

  defp render_all(ir) do
    with {:ok, ash_source} <- AshR2ml.Semantic.Ash.render(ir),
         {:ok, postgres_ddl} <- AshR2ml.Semantic.SQL.render(ir),
         {:ok, r2rml} <- AshR2ml.Semantic.R2RML.render(ir),
         {:ok, shacl} <- AshR2ml.Semantic.SHACL.render(ir) do
      receipt = receipt(ir, ash_source, postgres_ddl, r2rml, shacl)

      {:ok,
       %Compilation{
         status: :PARTIAL_ALIVE,
         standing: :constructed_not_actuated,
         ir: ir,
         ash_source: ash_source,
         postgres_ddl: postgres_ddl,
         r2rml: r2rml,
         shacl: shacl,
         receipt: receipt,
         refusals: []
       }}
    else
      {:error, reason} ->
        refusal = Refusal.new(:REFUSED_UNPROVEN_EQUIVALENCE, :projection, "renderer refused semantic IR", %{reason: inspect(reason)})
        {:error, %Compilation{status: :REFUSED, standing: :semantic_ir_only, ir: ir, refusals: [refusal], receipt: refusal_receipt([refusal], ir)}}
    end
  end

  defp projection_refusals(ir) do
    Enum.flat_map(ir.resources, fn resource ->
      Enum.flat_map(resource.relationships, fn relationship ->
        cond do
          is_nil(relationship.storage_strategy) ->
            [
              Refusal.new(
                :REFUSED_UNPROVEN_EQUIVALENCE,
                {resource.class_iri, relationship.name},
                "multiple lawful relational representations remain; select only after profile evidence closes the choice",
                %{candidates: relationship.storage_candidates}
              )
            ]

          relationship.storage_strategy == :association_resource ->
            [
              Refusal.new(
                :REFUSED_UNPROVEN_EQUIVALENCE,
                {resource.class_iri, relationship.name},
                "association-resource relationships must be reified as an admitted SemanticResource before executable projection",
                %{association_resource: relationship.association_resource}
              )
            ]

          true ->
            []
        end
      end)
    end)
  end

  defp receipt(ir, ash_source, postgres_ddl, r2rml, shacl) do
    resources = ir.resources

    %CompilationReceipt{
      status: :PARTIAL_ALIVE,
      standing: :constructed_not_actuated,
      ontology_hash: ir.ontology_hash,
      profile_hash: ir.profile_hash,
      shacl_input_hash: ir.shacl_hash,
      ir_sha256: sha256(canonical_ir(ir)),
      ash_sha256: sha256(ash_source),
      postgres_sha256: sha256(postgres_ddl),
      r2rml_sha256: sha256(r2rml),
      shacl_sha256: sha256(shacl),
      query_parity: :UNKNOWN,
      neo4j_postgres_parity: :UNKNOWN,
      classes_admitted: length(resources),
      attributes_admitted: Enum.sum(Enum.map(resources, &length(&1.attributes))),
      relationships_admitted: Enum.sum(Enum.map(resources, &length(&1.relationships))),
      actions_admitted: Enum.sum(Enum.map(resources, &length(&1.actions))),
      policies_admitted: Enum.sum(Enum.map(resources, &length(&1.policies))),
      storage_candidates: storage_map(resources, & &1.storage_candidates),
      selected_storage: storage_map(resources, & &1.storage_strategy),
      executed: [:admission, :semantic_ir, :ash_render, :postgres_render, :r2rml_render, :shacl_render],
      verified: [:single_ir_projection, :deterministic_render_identity],
      blocked: [:sparql_sql_behavioral_parity, :neo4j_postgres_semantic_parity, :cutover_authority],
      refusals: []
    }
  end

  defp refusal_receipt(refusals, ir \\ nil) do
    %CompilationReceipt{
      status: :REFUSED,
      standing: :no_cutover,
      ontology_hash: ir && ir.ontology_hash,
      profile_hash: ir && ir.profile_hash,
      shacl_input_hash: ir && ir.shacl_hash,
      query_parity: :UNKNOWN,
      neo4j_postgres_parity: :UNKNOWN,
      blocked: [:semantic_projection, :sparql_sql_behavioral_parity, :neo4j_postgres_semantic_parity, :cutover_authority],
      refusals: refusals
    }
  end

  defp storage_map(resources, value_fun) do
    Map.new(
      for resource <- resources,
          relationship <- resource.relationships do
        {{resource.class_iri, relationship.name}, value_fun.(relationship)}
      end
    )
  end

  defp canonical_ir(ir) do
    ir
    |> canonical_term()
    |> :erlang.term_to_binary([:deterministic])
  end

  defp canonical_term(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> canonical_term()
  end

  defp canonical_term(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> {key, canonical_term(value)} end)
    |> Enum.sort_by(fn {key, _value} -> inspect(key) end)
  end

  defp canonical_term(list) when is_list(list), do: Enum.map(list, &canonical_term/1)
  defp canonical_term(other), do: other

  defp sha256(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
end
