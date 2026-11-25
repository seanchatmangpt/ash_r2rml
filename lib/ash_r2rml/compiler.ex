# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.CompilationReceipt do
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

defmodule AshR2RML.Compiler do
  @moduledoc """
  Compiler from Ash resources to the canonical `AshR2RML.Mapping.Bundle` IR.

  This is CONSTRUCT only. It neither applies migrations nor starts any query
  runtime, and therefore cannot grant cutover standing by itself.

  Domains are expanded to their R2RML-mapped resources, then the closure of
  referenced parent resources is walked as a plain worklist (bounded by
  #{10_000} resources).

      {:ok, %AshR2RML.Mapping.Bundle{}} = AshR2RML.Compiler.compile(MyApp.Person)
  """

  alias AshR2RML.{CompilationReceipt, Refusal}

  @max_closure_resources 10_000

  @spec compile(module() | [module()], keyword()) ::
          {:ok, AshR2RML.Mapping.Bundle.t()} | {:error, Refusal.t()}
  def compile(resources, opts \\ [])

  def compile(resources, _opts) when is_atom(resources) or is_list(resources) do
    case compile_resources(resources) do
      {:ok, bundle} -> {:ok, bundle}
      {:error, refusal} -> {:error, refusal}
    end
  end

  @doc "Cutover requires an observed query-parity witness and an explicit authority receipt."
  def cutover_ready?(%CompilationReceipt{
        query_parity: :VERIFIED,
        cutover_authority: :AUTHORIZED,
        blocked: []
      }),
      do: true

  def cutover_ready?(_), do: false

  @doc "Attach an externally observed parity receipt without executing the compared systems."
  def attach_parity_witness(%CompilationReceipt{} = receipt, kind, witness)
      when kind == :sparql_sql and is_map(witness) do
    verified? = Map.get(witness, :verified?, Map.get(witness, "verified?", false))
    witness_id = Map.get(witness, :receipt_sha256, Map.get(witness, "receipt_sha256"))

    if verified? and is_binary(witness_id) and witness_id != "" do
      receipt = %{receipt | query_parity: :VERIFIED}
      blocked = List.delete(receipt.blocked, :sparql_sql_behavioral_parity)

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

  def attach_parity_witness(%CompilationReceipt{} = receipt, kind, witness) do
    refusal =
      Refusal.new(
        :REFUSED_UNPROVEN_EQUIVALENCE,
        kind,
        "unsupported parity witness kind or malformed witness; only :sparql_sql with a map witness is admitted",
        %{witness: witness}
      )

    %{receipt | refusals: [refusal | receipt.refusals]}
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

  def compile_resources(resources) do
    with {:ok, resources} <- expand_domains(List.wrap(resources)),
         {:ok, mappings} <- do_closure(resources, %{}, []) do
      bundle = %AshR2RML.Mapping.Bundle{resources: mappings} |> AshR2RML.Mapping.normalize()

      case AshR2RML.Mapping.validate(bundle) do
        :ok -> {:ok, bundle}
        {:error, [first | _]} -> {:error, first}
        {:error, []} -> {:ok, bundle}
      end
    end
  end

  defp expand_domains(items) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
      if domain?(item) do
        case AshR2RML.Resource.Info.domain_resources(item) do
          [] ->
            {:halt,
             {:error,
              Refusal.new(
                :REFUSED_MISSING_SUBJECT_MAP,
                item,
                "domain #{inspect(item)} has no resources carrying the AshR2RML extension"
              )}}

          mapped ->
            {:cont, {:ok, acc ++ mapped}}
        end
      else
        {:cont, {:ok, acc ++ [item]}}
      end
    end)
    |> case do
      {:ok, list} -> {:ok, Enum.uniq(list)}
      error -> error
    end
  end

  defp domain?(m) when is_atom(m) do
    Code.ensure_loaded?(m) and function_exported?(m, :spark_is, 0) and m.spark_is() == Ash.Domain
  end

  defp domain?(_), do: false

  defp do_closure([], _seen, acc), do: {:ok, Enum.reverse(acc)}

  defp do_closure([resource | rest], seen, acc) do
    cond do
      Map.has_key?(seen, resource) ->
        do_closure(rest, seen, acc)

      map_size(seen) >= @max_closure_resources ->
        {:error,
         Refusal.new(
           :REFUSED_RESOURCE_BOUND,
           :closure,
           "resource closure exceeds #{@max_closure_resources} resources",
           %{max_resources: @max_closure_resources}
         )}

      true ->
        closure_step(resource, rest, seen, acc)
    end
  end

  defp closure_step(resource, rest, seen, acc) do
    with {:ok, mapping} <- AshR2RML.Resource.Info.mapping_result(resource),
         mapping = AshR2RML.Security.sanitize_mapping(resource, mapping),
         :ok <- AshR2RML.Security.check_protected_dependencies(resource, mapping) do
      destinations = Enum.map(mapping.reference_object_maps, & &1.parent_resource) |> Enum.reject(&is_nil/1)

      do_closure(rest ++ destinations, Map.put(seen, resource, true), [mapping | acc])
    end
  end

  def sha256(value) when is_binary(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
  def sha256(value), do: value |> :erlang.term_to_binary([:deterministic]) |> sha256()
end
