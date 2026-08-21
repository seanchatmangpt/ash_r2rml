# SPDX-FileCopyrightText: 2026 ash_r2ml contributors <https://github.com/seanchatmangpt/ash_r2ml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2ml.CompilationReceipt do
  @moduledoc "Identity and standing record for one deterministic semantic compilation."

  defstruct [
    :status,
    :standing,
    :ontology_hash,
    :profile_hash,
    :shacl_input_hash,
    :ir_sha256,
    :mapping_sha256,
    :ash_sha256,
    :ecto_sha256,
    :postgres_sha256,
    :r2rml_sha256,
    :shacl_sha256,
    :query_parity,
    :neo4j_postgres_parity,
    :cutover_authority,
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

  @type t :: %__MODULE__{
          status: atom(),
          standing: atom(),
          ontology_hash: String.t() | nil,
          profile_hash: String.t() | nil,
          shacl_input_hash: String.t() | nil,
          ir_sha256: String.t() | nil,
          mapping_sha256: String.t() | nil,
          ash_sha256: String.t() | nil,
          ecto_sha256: String.t() | nil,
          postgres_sha256: String.t() | nil,
          r2rml_sha256: String.t() | nil,
          shacl_sha256: String.t() | nil,
          query_parity: :UNKNOWN | :VERIFIED,
          neo4j_postgres_parity: :UNKNOWN | :VERIFIED,
          cutover_authority: :UNAUTHORIZED | :AUTHORIZED | nil,
          classes_admitted: non_neg_integer(),
          attributes_admitted: non_neg_integer(),
          relationships_admitted: non_neg_integer(),
          actions_admitted: non_neg_integer(),
          policies_admitted: non_neg_integer(),
          storage_candidates: map(),
          selected_storage: map(),
          executed: list(),
          verified: list(),
          blocked: list(),
          refusals: list()
        }
end

defmodule AshR2ml.Compilation do
  @moduledoc "Evidence-bounded result of ontology-first semantic compilation."

  defstruct [
    :status,
    :standing,
    :ir,
    :mapping_bundle,
    :ash_source,
    :ecto_migration,
    :postgres_ddl,
    :r2rml,
    :shacl,
    :receipt,
    refusals: []
  ]

  @type t :: %__MODULE__{
          status: atom(),
          standing: atom(),
          ir: AshR2ml.SemanticIR.t() | nil,
          mapping_bundle: AshR2ML.Mapping.Bundle.t() | nil,
          ash_source: String.t() | nil,
          ecto_migration: String.t() | nil,
          postgres_ddl: String.t() | nil,
          r2rml: String.t() | nil,
          shacl: String.t() | nil,
          receipt: AshR2ml.CompilationReceipt.t() | nil,
          refusals: list()
        }
end

defmodule AshR2ml.Compiler do
  @moduledoc """
  Ontology-first compiler for the admitted closed operational profile.

  Pipeline:

      ontology/profile/SHACL-normalized input
          -> Admission
          -> SemanticIR
          -> AshR2ML.Mapping.Bundle
          -> Ash + Ecto + PostgreSQL + R2RML + SHACL
          -> CompilationReceipt

  The canonical public mapping bundle is the serialization boundary. The R2RML
  renderer never reaches back into SemanticIR or Ash to rediscover decisions.

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

  @doc "Cutover requires both observed parity witnesses and an explicit authority receipt."
  def cutover_ready?(%CompilationReceipt{
        query_parity: :VERIFIED,
        neo4j_postgres_parity: :VERIFIED,
        cutover_authority: :AUTHORIZED,
        blocked: []
      }),
      do: true

  def cutover_ready?(_), do: false

  @doc "Attach an externally observed parity receipt without executing the compared systems."
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

      %{
        receipt
        | blocked: blocked,
          verified: Enum.uniq([{:parity_witness, kind, witness_id} | receipt.verified])
      }
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

  @doc "Attach explicit cutover authority without conflating it with technical parity."
  def authorize_cutover(%CompilationReceipt{} = receipt, authority) when is_map(authority) do
    authorized? = Map.get(authority, :authorized?, Map.get(authority, "authorized?", false))
    authority_id = Map.get(authority, :receipt_sha256, Map.get(authority, "receipt_sha256"))

    if authorized? and is_binary(authority_id) and authority_id != "" do
      %{
        receipt
        | cutover_authority: :AUTHORIZED,
          blocked: List.delete(receipt.blocked, :cutover_authority),
          verified: Enum.uniq([{:cutover_authority, authority_id} | receipt.verified])
      }
    else
      refusal =
        Refusal.new(
          :REFUSED_UNPROVEN_EQUIVALENCE,
          :cutover_authority,
          "cutover authority requires authorized?: true and a stable receipt_sha256",
          %{authority: authority}
        )

      %{receipt | refusals: [refusal | receipt.refusals]}
    end
  end

  defp render_all(ir) do
    with {:ok, mapping_bundle} <- AshR2ML.SemanticAdapter.to_mapping(ir),
         :ok <- AshR2ML.Mapping.validate(mapping_bundle),
         {:ok, ash_source} <- AshR2ml.Semantic.Ash.render(ir),
         {:ok, ecto_migration} <- AshR2ml.Semantic.Ecto.render(ir),
         {:ok, postgres_ddl} <- AshR2ml.Semantic.SQL.render(ir),
         {:ok, r2rml} <- AshR2ML.R2RML.render(mapping_bundle),
         {:ok, shacl} <- AshR2ml.Semantic.SHACL.render(ir) do
      compilation_receipt =
        receipt(ir, mapping_bundle, ash_source, ecto_migration, postgres_ddl, r2rml, shacl)

      {:ok,
       %Compilation{
         status: :PARTIAL_ALIVE,
         standing: :constructed_not_actuated,
         ir: ir,
         mapping_bundle: mapping_bundle,
         ash_source: ash_source,
         ecto_migration: ecto_migration,
         postgres_ddl: postgres_ddl,
         r2rml: r2rml,
         shacl: shacl,
         receipt: compilation_receipt,
         refusals: []
       }}
    else
      {:error, [%AshR2ML.Refusal{} = refusal | _]} -> public_refusal_compilation(ir, refusal)
      {:error, %AshR2ML.Refusal{} = refusal} -> public_refusal_compilation(ir, refusal)
      {:error, %Refusal{} = refusal} -> refusal_compilation(ir, refusal)

      {:error, reason} ->
        refusal =
          Refusal.new(
            :REFUSED_UNPROVEN_EQUIVALENCE,
            :projection,
            "renderer refused semantic IR",
            %{reason: inspect(reason)}
          )

        refusal_compilation(ir, refusal)
    end
  end

  defp public_refusal_compilation(ir, public_refusal) do
    refusal =
      Refusal.new(
        :REFUSED_UNPROVEN_EQUIVALENCE,
        public_refusal.subject,
        "canonical mapping refused ontology-first projection: #{public_refusal.code}: #{public_refusal.detail}",
        %{public_refusal: Map.from_struct(public_refusal)}
      )

    refusal_compilation(ir, refusal)
  end

  defp refusal_compilation(ir, refusal) do
    {:error,
     %Compilation{
       status: :REFUSED,
       standing: :semantic_ir_only,
       ir: ir,
       refusals: [refusal],
       receipt: refusal_receipt([refusal], ir)
     }}
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

          true -> []
        end
      end)
    end)
  end

  defp receipt(ir, mapping_bundle, ash_source, ecto_migration, postgres_ddl, r2rml, shacl) do
    resources = ir.resources

    %CompilationReceipt{
      status: :PARTIAL_ALIVE,
      standing: :constructed_not_actuated,
      ontology_hash: ir.ontology_hash,
      profile_hash: ir.profile_hash,
      shacl_input_hash: ir.shacl_hash,
      ir_sha256: sha256(canonical_ir(ir)),
      mapping_sha256: sha256(canonical_term(mapping_bundle)),
      ash_sha256: sha256(ash_source),
      ecto_sha256: sha256(ecto_migration),
      postgres_sha256: sha256(postgres_ddl),
      r2rml_sha256: sha256(r2rml),
      shacl_sha256: sha256(shacl),
      query_parity: :UNKNOWN,
      neo4j_postgres_parity: :UNKNOWN,
      cutover_authority: :UNAUTHORIZED,
      classes_admitted: length(resources),
      attributes_admitted: Enum.sum(Enum.map(resources, &length(&1.attributes))),
      relationships_admitted: Enum.sum(Enum.map(resources, &length(&1.relationships))),
      actions_admitted: Enum.sum(Enum.map(resources, &length(&1.actions))),
      policies_admitted: Enum.sum(Enum.map(resources, &length(&1.policies))),
      storage_candidates: storage_map(resources, & &1.storage_candidates),
      selected_storage: storage_map(resources, & &1.storage_strategy),
      executed: [
        :admission,
        :semantic_ir,
        :canonical_mapping_ir,
        :ash_render,
        :ecto_render,
        :postgres_render,
        :r2rml_render,
        :shacl_render
      ],
      verified: [:canonical_mapping_ir_projection, :deterministic_render_identity],
      blocked: [
        :sparql_sql_behavioral_parity,
        :neo4j_postgres_semantic_parity,
        :cutover_authority
      ],
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
      cutover_authority: :UNAUTHORIZED,
      blocked: [
        :semantic_projection,
        :sparql_sql_behavioral_parity,
        :neo4j_postgres_semantic_parity,
        :cutover_authority
      ],
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

  defp canonical_ir(ir), do: canonical_term(ir)

  defp canonical_term(%_{} = struct), do: struct |> Map.from_struct() |> canonical_term()

  defp canonical_term(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> {key, canonical_term(value)} end)
    |> Enum.sort_by(fn {key, _value} -> inspect(key) end)
  end

  defp canonical_term(list) when is_list(list), do: Enum.map(list, &canonical_term/1)
  defp canonical_term(other), do: other

  defp sha256(value) when is_binary(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
  defp sha256(value), do: value |> :erlang.term_to_binary([:deterministic]) |> sha256()
end
