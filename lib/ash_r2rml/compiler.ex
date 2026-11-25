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
          query_parity: :UNKNOWN | :VERIFIED | nil,
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

  alias AshR2RML.Refusal

  @doc "Cutover requires an observed query-parity witness and an explicit authority receipt."
  @spec cutover_ready?(term()) :: boolean()
  def cutover_ready?(%__MODULE__{
        query_parity: :VERIFIED,
        cutover_authority: :AUTHORIZED,
        blocked: []
      }),
      do: true

  def cutover_ready?(_), do: false

  @doc "Attach an externally observed parity receipt without executing the compared systems."
  @spec attach_parity_witness(t(), term(), term()) :: t()
  def attach_parity_witness(%__MODULE__{} = receipt, kind, witness)
      when kind == :sparql_sql and is_map(witness) do
    verified? = Map.get(witness, :verified?, Map.get(witness, "verified?", false))
    witness_id = Map.get(witness, :receipt_sha256, Map.get(witness, "receipt_sha256"))

    if verified? == true and is_binary(witness_id) and witness_id != "" do
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

  def attach_parity_witness(%__MODULE__{} = receipt, kind, witness) do
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
  @spec authorize_cutover(t(), term()) :: t()
  def authorize_cutover(%__MODULE__{} = receipt, authority) do
    {authorized?, authority_id} = authority_fields(authority)

    if authorized? == true and is_binary(authority_id) and authority_id != "" do
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

  defp authority_fields(authority) when is_map(authority) do
    {Map.get(authority, :authorized?, Map.get(authority, "authorized?", false)),
     Map.get(authority, :receipt_sha256, Map.get(authority, "receipt_sha256"))}
  end

  defp authority_fields(_other), do: {false, nil}
end

defmodule AshR2RML.Compiler do
  @moduledoc """
  Compiler from Ash resources to the canonical `AshR2RML.Mapping.Bundle` IR.

  This is CONSTRUCT only. It neither applies migrations nor starts any query
  runtime, and therefore cannot grant cutover standing by itself (cutover helpers live on
  `AshR2RML.CompilationReceipt`).

  Domains are expanded to their R2RML-mapped resources, then the closure of
  referenced parent resources is walked as a plain worklist (bounded by
  #{10_000} resources).

      {:ok, %AshR2RML.Mapping.Bundle{}} = AshR2RML.Compiler.compile(MyApp.Person)
  """

  alias AshR2RML.Refusal

  @max_closure_resources 10_000

  @doc """
  Compiles an Ash resource, a domain, or a list of them into a dependency-closed
  `AshR2RML.Mapping.Bundle`.

  `compile/2` accepts no options: any option, a non-keyword `opts`, or an input that is not a
  module (or a list of modules) returns `{:error, %AshR2RML.Refusal{code: :REFUSED_INVALID_OPTION}}`.
  A module that carries no mapping returns `:REFUSED_MISSING_SUBJECT_MAP`.
  """
  @spec compile(module() | [module()], keyword()) ::
          {:ok, AshR2RML.Mapping.Bundle.t()} | {:error, Refusal.t()}
  def compile(resources, opts \\ []) do
    with :ok <- validate_opts(opts),
         :ok <- validate_input(resources) do
      compile_resources(resources)
    end
  end

  defp validate_opts([]), do: :ok

  defp validate_opts(opts) do
    detail =
      if Keyword.keyword?(opts),
        do: "compile/2 accepts no options, got #{inspect(opts)}",
        else: "options must be a keyword list, got #{inspect(opts)}"

    {:error, invalid_input(:opts, detail)}
  end

  defp validate_input(resources) when is_list(resources), do: :ok
  defp validate_input(resources) when is_atom(resources) and not is_nil(resources), do: :ok

  defp validate_input(other) do
    {:error, invalid_input(:resources, "expected a resource, a domain, or a list of them, got #{inspect(other)}")}
  end

  defp invalid_input(option, detail) do
    Refusal.new(:REFUSED_INVALID_OPTION, :compile, detail, %{option: option})
  end

  @doc """
  Compiles resources and/or domains into a validated, normalized bundle.

  Same contract as `compile/2`; `compile/2` is the public entry point. When validation yields
  several refusals, the first is returned and the rest ride in `evidence.additional_refusals`.
  """
  @spec compile_resources(module() | [module()]) ::
          {:ok, AshR2RML.Mapping.Bundle.t()} | {:error, Refusal.t()}
  def compile_resources(resources) do
    with {:ok, resources} <- expand_domains(List.wrap(resources)),
         {:ok, mappings} <- do_closure(:queue.from_list(resources), %{}, []) do
      bundle = %AshR2RML.Mapping.Bundle{resources: mappings} |> AshR2RML.Mapping.normalize()

      case AshR2RML.Mapping.validate(bundle) do
        :ok -> {:ok, bundle}
        {:error, [first | rest]} -> {:error, with_additional(first, rest)}
      end
    end
  end

  defp with_additional(first, []), do: first

  defp with_additional(%Refusal{evidence: evidence} = first, rest) when is_map(evidence) do
    %{first | evidence: Map.put(evidence, :additional_refusals, rest)}
  end

  defp expand_domains(items) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      if is_atom(item) and not is_nil(item) do
        expand_domain_or_resource(item, acc)
      else
        {:halt, {:error, invalid_input(:resources, "expected resource or domain modules, got #{inspect(item)}")}}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, reversed |> Enum.reverse() |> Enum.uniq()}
      error -> error
    end
  end

  defp expand_domain_or_resource(item, acc) do
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
          {:cont, {:ok, Enum.reverse(mapped, acc)}}
      end
    else
      {:cont, {:ok, [item | acc]}}
    end
  end

  defp domain?(m) when is_atom(m) do
    Code.ensure_loaded?(m) and Spark.Dsl.is?(m, Ash.Domain)
  end

  # Breadth-first worklist over a queue. Destinations already seen are dropped before they
  # are enqueued, so the queue never grows with resources that are already mapped.
  defp do_closure(queue, seen, acc) do
    case :queue.out(queue) do
      {:empty, _} ->
        {:ok, Enum.reverse(acc)}

      {{:value, resource}, rest} ->
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
  end

  defp closure_step(resource, rest, seen, acc) do
    with {:ok, mapping} <- AshR2RML.Resource.Info.mapping_result(resource),
         mapping = AshR2RML.Security.sanitize_mapping(resource, mapping),
         :ok <- AshR2RML.Security.check_protected_dependencies(resource, mapping) do
      seen = Map.put(seen, resource, true)

      queue =
        mapping.reference_object_maps
        |> Enum.map(& &1.parent_resource)
        |> Enum.reject(&(is_nil(&1) or Map.has_key?(seen, &1)))
        |> Enum.reduce(rest, &:queue.in/2)

      do_closure(queue, seen, [mapping | acc])
    end
  end

  @doc "Lowercase hex SHA-256 of a binary, or of the deterministic external term format of any term."
  @spec sha256(term()) :: String.t()
  def sha256(value) when is_binary(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
  def sha256(value), do: value |> :erlang.term_to_binary([:deterministic]) |> sha256()
end
