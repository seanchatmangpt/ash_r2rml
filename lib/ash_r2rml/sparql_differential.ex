# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.SPARQL.DifferentialReceipt do
  @moduledoc "Stable multi-engine SPARQL semantic-differential receipt."

  @enforce_keys [
    :subject,
    :query_sha256,
    :strategies,
    :result_sha256_by_strategy,
    :verified?,
    :receipt_sha256
  ]
  defstruct [
    :subject,
    :query_sha256,
    :strategies,
    :result_sha256_by_strategy,
    :verified?,
    :receipt_sha256,
    row_count_by_strategy: %{},
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          subject: term(),
          query_sha256: String.t(),
          strategies: [AshR2RML.SPARQL.Plan.strategy()],
          result_sha256_by_strategy: %{atom() => String.t()},
          verified?: boolean(),
          receipt_sha256: String.t(),
          row_count_by_strategy: %{atom() => non_neg_integer()},
          metadata: map()
        }
end

defmodule AshR2RML.SPARQL.Differential do
  @moduledoc """
  Compares multiple observed SPARQL execution topologies without privileging one.

  A differential receipt is evidence over observations of the **same admitted
  lexical query**. It is deliberately not used to claim equivalence between
  different SPARQL query strings, even when a human believes them equivalent.

  Observation order is irrelevant; fewer than two strategies, duplicate
  strategies, and mixed query identities fail closed.
  """

  alias AshR2RML.Refusal
  alias AshR2RML.SPARQL.{DifferentialReceipt, Observation, Result}

  @spec compare(term(), [Observation.t()], map()) ::
          {:ok, DifferentialReceipt.t()} | {:error, Refusal.t()}
  def compare(subject, observations, metadata \\ %{})

  def compare(subject, observations, metadata) when is_list(observations) and is_map(metadata) do
    with :ok <- require_observations(observations),
         {:ok, query_sha256} <- common_query_identity(observations),
         :ok <- unique_strategies(observations) do
      ordered = Enum.sort_by(observations, &to_string(&1.strategy))

      hashes =
        Map.new(ordered, fn observation ->
          {observation.strategy, Result.hash_rows(observation.rows)}
        end)

      counts = Map.new(ordered, &{&1.strategy, length(&1.rows)})
      distinct_results = hashes |> Map.values() |> MapSet.new() |> MapSet.size()

      seed = %{
        subject: subject,
        query_sha256: query_sha256,
        strategies: Enum.map(ordered, & &1.strategy),
        result_sha256_by_strategy: hashes,
        row_count_by_strategy: counts,
        verified?: distinct_results == 1,
        metadata: metadata
      }

      {:ok, struct!(DifferentialReceipt, Map.put(seed, :receipt_sha256, sha256(canonical(seed))))}
    end
  end

  def compare(subject, other, metadata) do
    {:error,
     Refusal.new(
       :REFUSED_UNPROVEN_EQUIVALENCE,
       subject,
       "SPARQL differential requires an observation list and metadata map",
       %{observations: inspect(other), metadata: inspect(metadata)}
     )}
  end

  @doc "Require a specific observation topology before promoting a differential receipt."
  @spec require_strategies(DifferentialReceipt.t(), [AshR2RML.SPARQL.Plan.strategy()]) ::
          :ok | {:error, Refusal.t()}
  def require_strategies(%DifferentialReceipt{} = receipt, required) when is_list(required) do
    missing = required -- receipt.strategies

    cond do
      missing != [] ->
        {:error,
         Refusal.new(
           :REFUSED_UNPROVEN_EQUIVALENCE,
           receipt.subject,
           "SPARQL differential receipt is missing required execution topologies",
           %{required: required, observed: receipt.strategies, missing: missing}
         )}

      not receipt.verified? ->
        {:error,
         Refusal.new(
           :REFUSED_UNPROVEN_EQUIVALENCE,
           receipt.subject,
           "required SPARQL execution topologies produced different normalized multisets",
           %{result_sha256_by_strategy: receipt.result_sha256_by_strategy}
         )}

      true ->
        :ok
    end
  end

  defp require_observations(observations) when length(observations) < 2 do
    {:error,
     Refusal.new(
       :REFUSED_UNPROVEN_EQUIVALENCE,
       :sparql_differential,
       "semantic differential requires observations from at least two execution strategies",
       %{observation_count: length(observations)}
     )}
  end

  defp require_observations(observations) do
    if Enum.all?(observations, &match?(%Observation{}, &1)) do
      :ok
    else
      {:error,
       Refusal.new(
         :REFUSED_UNPROVEN_EQUIVALENCE,
         :sparql_differential,
         "all differential inputs must be AshR2RML.SPARQL.Observation values"
       )}
    end
  end

  defp common_query_identity(observations) do
    identities = observations |> Enum.map(& &1.query_sha256) |> Enum.uniq()

    case identities do
      [identity] when is_binary(identity) and identity != "" ->
        {:ok, identity}

      _ ->
        {:error,
         Refusal.new(
           :REFUSED_UNPROVEN_EQUIVALENCE,
           :sparql_differential,
           "semantic differential requires observations of one admitted lexical query",
           %{query_sha256s: identities}
         )}
    end
  end

  defp unique_strategies(observations) do
    strategies = Enum.map(observations, & &1.strategy)

    if length(strategies) == MapSet.size(MapSet.new(strategies)) do
      :ok
    else
      {:error,
       Refusal.new(
         :REFUSED_UNPROVEN_EQUIVALENCE,
         :sparql_differential,
         "each SPARQL execution strategy may contribute at most one observation",
         %{strategies: strategies}
       )}
    end
  end

  defp canonical(%_{} = struct), do: struct |> Map.from_struct() |> canonical()

  defp canonical(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> {key, canonical(value)} end)
    |> Enum.sort_by(fn {key, _value} -> inspect(key) end)
  end

  defp canonical(list) when is_list(list), do: Enum.map(list, &canonical/1)
  defp canonical(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> Enum.map(&canonical/1)
  defp canonical(other), do: other

  defp sha256(value) when is_binary(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
  defp sha256(value), do: value |> :erlang.term_to_binary([:deterministic]) |> sha256()
end
