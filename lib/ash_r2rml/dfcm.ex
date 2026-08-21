# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.DfCM do
  @moduledoc """
  Design for Combinatorial Maximalism as a bounded, deterministic calculus.

  DfCM preserves the lawful reversible design space until evidence or explicit
  authority closes a choice. It is intentionally generic: deployment, storage,
  runtime and organizational quality policies are consumers of this module,
  not concepts built into it.

  The module is SELECT-only. It never applies a candidate to a runtime system.
  """

  defmodule Dimension do
    @moduledoc "A reversible design dimension with a finite admitted option set."
    @enforce_keys [:id, :options]
    defstruct [:id, :description, :default, options: [], metadata: %{}]

    @type t :: %__MODULE__{}
  end

  defmodule Constraint do
    @moduledoc "A declarative implication/refusal over candidate assignments."
    @enforce_keys [:id]
    defstruct [:id, :description, severity: :hard, match: %{}, require: %{}, forbid: %{}]

    @type t :: %__MODULE__{}
  end

  defmodule Space do
    @moduledoc "A deterministic finite product plus declarative constraints and bounds."
    defstruct dimensions: [], constraints: [], bounds: %{max_examined: 100_000, max_candidates: 1_000}

    @type t :: %__MODULE__{}
  end

  defmodule Candidate do
    @moduledoc "One admitted reversible candidate."
    @enforce_keys [:id, :assignment]
    defstruct [:id, :assignment, advisory: [], metadata: %{}]

    @type t :: %__MODULE__{}
  end

  defmodule Refusal do
    @moduledoc "A typed DfCM refusal."
    @enforce_keys [:code, :subject, :detail]
    defstruct [:code, :subject, :detail, evidence: %{}]

    @type t :: %__MODULE__{}
  end

  defmodule EnumerationReceipt do
    @moduledoc "Exact receipt for one bounded traversal of a design space."
    defstruct [
      :space_sha256,
      :selection_sha256,
      :logical_cardinality,
      :examined,
      :admitted,
      :refused,
      :truncated,
      :receipt_sha256
    ]

    @type t :: %__MODULE__{}
  end

  defmodule SelectionReceipt do
    @moduledoc "Receipt proving an explicit choice without granting execution authority."
    defstruct [:candidate_id, :space_sha256, :authority_receipt_sha256, :receipt_sha256]

    @type t :: %__MODULE__{}
  end

  @type selection :: %{optional(atom()) => term()}

  @spec new([Dimension.t()], [Constraint.t()], keyword()) :: {:ok, Space.t()} | {:error, Refusal.t()}
  def new(dimensions, constraints \\ [], opts \\ []) when is_list(dimensions) and is_list(constraints) do
    space = %Space{
      dimensions: dimensions,
      constraints: constraints,
      bounds: %{
        max_examined: Keyword.get(opts, :max_examined, 100_000),
        max_candidates: Keyword.get(opts, :max_candidates, 1_000)
      }
    }

    case validate_space(space) do
      :ok -> {:ok, normalize_space(space)}
      {:error, refusal} -> {:error, refusal}
    end
  end

  @spec logical_cardinality(Space.t(), map()) :: non_neg_integer()
  def logical_cardinality(%Space{} = space, selection \\ %{}) do
    case normalize_selection(space, selection) do
      {:ok, selected} ->
        Enum.reduce(space.dimensions, 1, fn dimension, total ->
          if Map.has_key?(selected, dimension.id), do: total, else: total * length(dimension.options)
        end)

      {:error, _} ->
        0
    end
  end

  @spec enumerate(Space.t(), keyword()) ::
          {:ok, [Candidate.t()], EnumerationReceipt.t()} | {:error, Refusal.t()}
  def enumerate(%Space{} = space, opts \\ []) do
    selection = Keyword.get(opts, :select, %{})
    max_examined = Keyword.get(opts, :max_examined, space.bounds.max_examined)
    max_candidates = Keyword.get(opts, :max_candidates, space.bounds.max_candidates)

    with :ok <- validate_positive_bound(:max_examined, max_examined),
         :ok <- validate_positive_bound(:max_candidates, max_candidates),
         {:ok, selected} <- normalize_selection(space, selection) do
      stream = assignment_stream(space.dimensions, selected)

      initial = %{examined: 0, admitted: [], refused: 0, ended?: true}

      state =
        Enum.reduce_while(stream, initial, fn assignment, acc ->
          cond do
            acc.examined >= max_examined ->
              {:halt, %{acc | ended?: false}}

            length(acc.admitted) >= max_candidates ->
              {:halt, %{acc | ended?: false}}

            true ->
              examined = acc.examined + 1

              case admit(space, assignment) do
                {:ok, candidate} ->
                  {:cont, %{acc | examined: examined, admitted: [candidate | acc.admitted]}}

                {:error, _refusals} ->
                  {:cont, %{acc | examined: examined, refused: acc.refused + 1}}
              end
          end
        end)

      candidates = state.admitted |> Enum.reverse() |> Enum.sort_by(& &1.id)
      logical_cardinality = logical_cardinality(space, selected)

      base = %EnumerationReceipt{
        space_sha256: space_sha256(space),
        selection_sha256: sha256(selected),
        logical_cardinality: logical_cardinality,
        examined: state.examined,
        admitted: length(candidates),
        refused: state.refused,
        truncated: not state.ended? or state.examined < logical_cardinality,
        receipt_sha256: nil
      }

      receipt = %{base | receipt_sha256: sha256(Map.from_struct(base))}
      {:ok, candidates, receipt}
    end
  end

  @spec admit(Space.t(), map()) :: {:ok, Candidate.t()} | {:error, [Refusal.t()]}
  def admit(%Space{} = space, assignment) when is_map(assignment) do
    with {:ok, normalized} <- normalize_assignment(space, assignment) do
      {hard, advisory} = evaluate_constraints(space.constraints, normalized)

      if hard == [] do
        {:ok,
         %Candidate{
           id: sha256(normalized),
           assignment: normalized,
           advisory: Enum.sort_by(advisory, & &1.subject)
         }}
      else
        {:error, Enum.sort_by(hard, & &1.subject)}
      end
    else
      {:error, refusal} -> {:error, [refusal]}
    end
  end

  @spec select(Space.t(), Candidate.t(), map()) :: {:ok, SelectionReceipt.t()} | {:error, Refusal.t()}
  def select(%Space{} = space, %Candidate{} = candidate, authority) when is_map(authority) do
    authorized? = fetch(authority, :authorized?, false)
    authority_receipt = fetch(authority, :receipt_sha256, nil)

    with true <- authorized? == true,
         true <- is_binary(authority_receipt) and byte_size(authority_receipt) > 0,
         {:ok, admitted} <- admit(space, candidate.assignment),
         true <- admitted.id == candidate.id do
      base = %SelectionReceipt{
        candidate_id: candidate.id,
        space_sha256: space_sha256(space),
        authority_receipt_sha256: authority_receipt,
        receipt_sha256: nil
      }

      {:ok, %{base | receipt_sha256: sha256(Map.from_struct(base))}}
    else
      _ ->
        {:error,
         refusal(
           :REFUSED_DFCM_SELECTION_WITHOUT_AUTHORITY,
           candidate.id,
           "selection requires an admitted candidate and an explicit authority receipt",
           %{authority: redact_authority(authority)}
         )}
    end
  end

  @spec frontier([Candidate.t()], [{atom(), :min | :max}]) :: [Candidate.t()]
  def frontier(candidates, objectives \\ []) when is_list(candidates) and is_list(objectives) do
    if objectives == [] do
      Enum.sort_by(candidates, & &1.id)
    else
      candidates
      |> Enum.reject(fn candidate ->
        Enum.any?(candidates, fn other ->
          other.id != candidate.id and dominates?(other, candidate, objectives)
        end)
      end)
      |> Enum.sort_by(& &1.id)
    end
  end

  @spec space_sha256(Space.t()) :: String.t()
  def space_sha256(%Space{} = space), do: sha256(normalize_space(space))

  @spec sha256(term()) :: String.t()
  def sha256(term) do
    term
    |> canonical()
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp validate_space(%Space{dimensions: []}) do
    {:error, refusal(:REFUSED_DFCM_EMPTY_SPACE, :space, "at least one design dimension is required")}
  end

  defp validate_space(%Space{} = space) do
    ids = Enum.map(space.dimensions, & &1.id)

    cond do
      Enum.any?(space.dimensions, &(not is_atom(&1.id) or &1.options == [])) ->
        {:error,
         refusal(
           :REFUSED_DFCM_INVALID_DIMENSION,
           :dimensions,
           "dimension ids must be atoms and option sets must be non-empty"
         )}

      length(ids) != length(Enum.uniq(ids)) ->
        {:error,
         refusal(:REFUSED_DFCM_DUPLICATE_DIMENSION, :dimensions, "dimension ids must be unique")}

      Enum.any?(space.dimensions, &(&1.default != nil and &1.default not in &1.options)) ->
        {:error,
         refusal(:REFUSED_DFCM_INVALID_DEFAULT, :dimensions, "dimension defaults must be admitted options")}

      true ->
        :ok
    end
  end

  defp validate_positive_bound(name, value) when is_integer(value) and value > 0, do: :ok

  defp validate_positive_bound(name, value) do
    {:error,
     refusal(:REFUSED_DFCM_INVALID_BOUND, name, "enumeration bounds must be positive integers", %{
       value: value
     })}
  end

  defp normalize_space(%Space{} = space) do
    %{
      space
      | dimensions:
          space.dimensions
          |> Enum.map(fn dimension ->
            %{dimension | options: Enum.uniq(dimension.options), metadata: canonical(dimension.metadata)}
          end)
          |> Enum.sort_by(& &1.id),
        constraints: Enum.sort_by(space.constraints, & &1.id)
    }
  end

  defp normalize_selection(%Space{} = space, selection) when is_list(selection) do
    normalize_selection(space, Map.new(selection))
  end

  defp normalize_selection(%Space{} = space, selection) when is_map(selection) do
    dimensions = Map.new(space.dimensions, &{&1.id, &1})

    Enum.reduce_while(selection, {:ok, %{}}, fn {raw_key, raw_value}, {:ok, acc} ->
      case resolve_dimension(dimensions, raw_key) do
        nil ->
          {:halt,
           {:error,
            refusal(
              :REFUSED_DFCM_UNKNOWN_DIMENSION,
              raw_key,
              "selection references a dimension outside the admitted space"
            )}}

        %Dimension{} = dimension ->
          case resolve_option(dimension.options, raw_value) do
            {:ok, value} -> {:cont, {:ok, Map.put(acc, dimension.id, value)}}
            :error ->
              {:halt,
               {:error,
                refusal(
                  :REFUSED_DFCM_UNKNOWN_OPTION,
                  dimension.id,
                  "selection references an option outside the admitted dimension",
                  %{value: raw_value, options: dimension.options}
                )}}
          end
      end
    end)
  end

  defp normalize_selection(_space, selection) do
    {:error,
     refusal(:REFUSED_DFCM_INVALID_SELECTION, :selection, "selection must be a map or keyword list", %{
       selection: inspect(selection)
     })}
  end

  defp normalize_assignment(%Space{} = space, assignment) do
    expected = MapSet.new(Enum.map(space.dimensions, & &1.id))
    supplied = MapSet.new(Map.keys(assignment))

    if expected == supplied do
      normalize_selection(space, assignment)
    else
      {:error,
       refusal(
         :REFUSED_DFCM_INCOMPLETE_ASSIGNMENT,
         :assignment,
         "candidate assignment must contain every dimension exactly once",
         %{
           missing: expected |> MapSet.difference(supplied) |> MapSet.to_list() |> Enum.sort(),
           extra: supplied |> MapSet.difference(expected) |> MapSet.to_list() |> Enum.sort()
         }
       )}
    end
  end

  defp resolve_dimension(dimensions, key) when is_atom(key), do: Map.get(dimensions, key)

  defp resolve_dimension(dimensions, key) when is_binary(key) do
    Enum.find_value(dimensions, fn {id, dimension} -> if Atom.to_string(id) == key, do: dimension end)
  end

  defp resolve_dimension(_dimensions, _key), do: nil

  defp resolve_option(options, value) do
    cond do
      value in options -> {:ok, value}
      is_binary(value) ->
        case Enum.find(options, &(to_string(&1) == value)) do
          nil -> :error
          option -> {:ok, option}
        end
      true -> :error
    end
  end

  defp assignment_stream(dimensions, selected) do
    Enum.reduce(dimensions, Stream.map([%{}], & &1), fn dimension, stream ->
      options =
        case Map.fetch(selected, dimension.id) do
          {:ok, option} -> [option]
          :error -> dimension.options
        end

      Stream.flat_map(stream, fn assignment ->
        Stream.map(options, &Map.put(assignment, dimension.id, &1))
      end)
    end)
  end

  defp evaluate_constraints(constraints, assignment) do
    Enum.reduce(constraints, {[], []}, fn constraint, {hard, advisory} ->
      case evaluate_constraint(constraint, assignment) do
        :ok -> {hard, advisory}
        {:error, refusal} when constraint.severity == :advisory -> {hard, [refusal | advisory]}
        {:error, refusal} -> {[refusal | hard], advisory}
      end
    end)
  end

  defp evaluate_constraint(%Constraint{} = constraint, assignment) do
    if subset_match?(assignment, constraint.match) do
      missing =
        constraint.require
        |> Enum.reject(fn {key, expected} -> value_allowed?(Map.get(assignment, key), expected) end)
        |> Map.new()

      forbidden =
        constraint.forbid
        |> Enum.filter(fn {key, expected} -> value_allowed?(Map.get(assignment, key), expected) end)
        |> Map.new()

      if map_size(missing) == 0 and map_size(forbidden) == 0 do
        :ok
      else
        {:error,
         refusal(
           :REFUSED_DFCM_CONSTRAINT,
           constraint.id,
           constraint.description || "candidate violates a design-space constraint",
           %{missing_requirements: missing, forbidden_matches: forbidden}
         )}
      end
    else
      :ok
    end
  end

  defp subset_match?(assignment, expected) do
    Enum.all?(expected, fn {key, value} -> value_allowed?(Map.get(assignment, key), value) end)
  end

  defp value_allowed?(actual, expected) when is_list(expected), do: actual in expected
  defp value_allowed?(actual, expected), do: actual == expected

  defp dominates?(left, right, objectives) do
    comparisons =
      Enum.map(objectives, fn {key, direction} ->
        left_value = get_in(left.metadata, [:metrics, key])
        right_value = get_in(right.metadata, [:metrics, key])
        compare_objective(left_value, right_value, direction)
      end)

    Enum.all?(comparisons, &(&1 in [:equal, :better])) and Enum.any?(comparisons, &(&1 == :better))
  end

  defp compare_objective(nil, _right, _direction), do: :worse
  defp compare_objective(_left, nil, _direction), do: :better
  defp compare_objective(left, right, _direction) when left == right, do: :equal
  defp compare_objective(left, right, :min) when left < right, do: :better
  defp compare_objective(_left, _right, :min), do: :worse
  defp compare_objective(left, right, :max) when left > right, do: :better
  defp compare_objective(_left, _right, :max), do: :worse

  defp refusal(code, subject, detail, evidence \\ %{}) do
    %Refusal{code: code, subject: subject, detail: detail, evidence: evidence}
  end

  defp redact_authority(authority) do
    authority
    |> Map.take([:authorized?, "authorized?"])
    |> Map.put(:receipt_present?, is_binary(fetch(authority, :receipt_sha256, nil)))
  end

  defp fetch(map, key, default) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp canonical(%_{} = struct), do: struct |> Map.from_struct() |> canonical()

  defp canonical(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> {canonical(key), canonical(value)} end)
    |> Enum.sort_by(fn {key, _value} -> inspect(key) end)
  end

  defp canonical(list) when is_list(list), do: Enum.map(list, &canonical/1)
  defp canonical(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> canonical()
  defp canonical(value), do: value
end
