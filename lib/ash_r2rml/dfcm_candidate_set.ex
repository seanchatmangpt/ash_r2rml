# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.DfCM.CandidateSet do
  @moduledoc """
  Reversible EXPLORE-time narrowing for relationship storage candidates.

  The semantic compiler already distinguishes a candidate set from a selected
  `storage_strategy`. This module adds the missing middle state: a closed
  application profile may rule out some lawful candidates while still leaving
  more than one reversible representation alive.

  Narrowing never selects on behalf of the caller. `select/3` requires an
  explicit choice and delegates implementation support to `AshR2RML.DfCM`, so
  unimplemented strategies remain typed refusals instead of being silently
  converted into another representation.
  """

  alias AshR2RML.{DfCM, Refusal}
  alias AshR2RML.SemanticIR.Relationship

  @known [
    :foreign_key,
    :join_table,
    :association_resource,
    :array,
    :jsonb,
    :computed_projection
  ]

  @type candidate :: Relationship.storage_strategy()

  @spec narrow(Relationship.t(), [candidate() | String.t()]) ::
          {:ok, Relationship.t()} | {:error, Refusal.t()}
  def narrow(%Relationship{} = relationship, admitted) when is_list(admitted) do
    universe = DfCM.storage_candidates(relationship)

    with {:ok, requested} <- normalize(admitted, relationship),
         :ok <- require_nonempty(requested, relationship),
         :ok <- require_subset(requested, universe, relationship) do
      candidates = Enum.filter(universe, &(&1 in requested))

      if is_nil(relationship.storage_strategy) or relationship.storage_strategy in candidates do
        {:ok, %{relationship | storage_candidates: candidates}}
      else
        {:error,
         Refusal.new(
           :REFUSED_AMBIGUOUS_RELATIONSHIP,
           relationship.name,
           "selected storage strategy is outside the admitted candidate set",
           %{selected: relationship.storage_strategy, admitted_candidates: candidates}
         )}
      end
    end
  end

  def narrow(%Relationship{} = relationship, other) do
    {:error,
     Refusal.new(
       :REFUSED_AMBIGUOUS_RELATIONSHIP,
       relationship.name,
       "admitted storage candidates must be a list",
       %{admitted_candidates: other}
     )}
  end

  @spec select(Relationship.t(), [candidate() | String.t()], candidate() | String.t()) ::
          {:ok, Relationship.t()} | {:error, Refusal.t()}
  def select(%Relationship{} = relationship, admitted, selected) do
    with {:ok, narrowed} <- narrow(relationship, admitted),
         {:ok, [strategy]} <- normalize([selected], relationship),
         :ok <- require_selected(strategy, narrowed),
         {:ok, selected_relationship} <- DfCM.select(%{narrowed | storage_strategy: strategy}) do
      {:ok, %{selected_relationship | storage_candidates: narrowed.storage_candidates}}
    end
  end

  @doc "Returns true only when two candidate lists normalize to the same canonical lawful set."
  @spec equivalent?(Relationship.t(), list(), list()) :: boolean()
  def equivalent?(%Relationship{} = relationship, left, right) do
    with {:ok, l} <- narrow(%{relationship | storage_strategy: nil}, left),
         {:ok, r} <- narrow(%{relationship | storage_strategy: nil}, right) do
      l.storage_candidates == r.storage_candidates
    else
      _ -> false
    end
  end

  defp normalize(values, relationship) do
    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
      case normalize_candidate(value) do
        {:ok, candidate} -> {:cont, {:ok, [candidate | acc]}}

        :error ->
          {:halt,
           {:error,
            Refusal.new(
              :REFUSED_AMBIGUOUS_RELATIONSHIP,
              relationship.name,
              "unknown storage candidate in admitted candidate set",
              %{candidate: value, known_candidates: @known}
            )}}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, normalized |> Enum.reverse() |> Enum.uniq()}
      error -> error
    end
  end

  defp normalize_candidate(value) when value in @known, do: {:ok, value}

  defp normalize_candidate(value) when is_binary(value) do
    case Enum.find(@known, &(Atom.to_string(&1) == value)) do
      nil -> :error
      candidate -> {:ok, candidate}
    end
  end

  defp normalize_candidate(_), do: :error

  defp require_nonempty([], relationship) do
    {:error,
     Refusal.new(
       :REFUSED_AMBIGUOUS_RELATIONSHIP,
       relationship.name,
       "closed candidate admission cannot eliminate every storage representation"
     )}
  end

  defp require_nonempty(_, _), do: :ok

  defp require_subset(requested, universe, relationship) do
    invalid = Enum.reject(requested, &(&1 in universe))

    if invalid == [] do
      :ok
    else
      {:error,
       Refusal.new(
         :REFUSED_CARDINALITY_STORAGE_MISMATCH,
         relationship.name,
         "admitted candidate set contains strategies that are unlawful for this relationship cardinality",
         %{invalid_candidates: invalid, lawful_candidates: universe}
       )}
    end
  end

  defp require_selected(strategy, %Relationship{storage_candidates: candidates} = relationship) do
    if strategy in candidates do
      :ok
    else
      {:error,
       Refusal.new(
         :REFUSED_AMBIGUOUS_RELATIONSHIP,
         relationship.name,
         "explicit selection must come from the admitted candidate set",
         %{selected: strategy, admitted_candidates: candidates}
       )}
    end
  end
end
