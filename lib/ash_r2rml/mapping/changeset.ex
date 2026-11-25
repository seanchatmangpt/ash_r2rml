# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Mapping.Changeset do
  @moduledoc """
  Structured `add`/`update`/`replace`/`remove` diff between two `RDF.Graph`
  snapshots of a rendered mapping (e.g. two successive R2RML Turtle renders of
  the same `AshR2RML.Mapping.Resource`, or two successive
  `AshR2RML.OBDA.InMemory.materialize/3` snapshots).

  Ported from Gno's `Gno.Changeset` action-graph algebra
  (`~/gno/lib/gno/changeset/{changeset,action,validation}.ex`), stripped of
  everything that assumes a live, queryable triple store: Gno's changeset is
  ultimately applied to and diffed against a running SPARQL store via
  `Gno.EffectiveChangeset.Query`'s SPARQL-CONSTRUCT algorithm. AshR2RML never
  has such a store -- a virtual OBDA engine is not a materialized
  graph -- so this module keeps only the store-independent half: the action
  vocabulary (`add`/`update`/`replace`/`remove`), its mutual-exclusion
  validation rules, and inversion, all as pure `RDF.Graph` transformations.

  ## Action semantics

    * `:add` -- statements present in the new snapshot but absent from the old
    * `:remove` -- statements present in the old snapshot but absent from the new
    * `:update` -- statements whose subject+predicate persist across both
      snapshots but whose object changed (a predicate-level replacement)
    * `:replace` -- statements for a subject that exists in both snapshots but
      whose entire description changed (a subject-level replacement); mutually
      exclusive with `:update` for the same subject, matching Gno's validation
      rule that a subject cannot be both partially updated and wholly replaced
      in the same changeset

  Use `diff/2` to compute a changeset between two snapshots. `diff/2` is a pure
  add/remove diff; it never emits `:update` or `:replace`. Those two actions
  are only populated by callers building a changeset directly with `new/1`.
  """

  alias AshR2RML.RDF.GraphAlgebra
  alias AshR2RML.Refusal
  alias RDF.Graph

  defstruct add: nil, update: nil, replace: nil, remove: nil

  @type t :: %__MODULE__{
          add: Graph.t() | nil,
          update: Graph.t() | nil,
          replace: Graph.t() | nil,
          remove: Graph.t() | nil
        }

  @action_fields [:add, :update, :replace, :remove]

  @doc "The changeset action field names, in a fixed, deterministic order."
  @spec action_fields() :: [atom()]
  def action_fields, do: @action_fields

  @doc """
  Builds a changeset from keyword/map options; each of `:add`, `:update`,
  `:replace`, `:remove` is optional and defaults to `nil` (no statements for
  that action). Returns `{:error, %Refusal{}}` if validation fails.
  """
  @spec new(keyword() | map()) :: {:ok, t()} | {:error, Refusal.t()}
  def new(opts \\ [])

  def new(opts) when is_map(opts), do: build(opts)

  def new(opts) when is_list(opts) do
    if Keyword.keyword?(opts), do: build(opts), else: {:error, invalid_input(:options, opts)}
  end

  def new(other), do: {:error, invalid_input(:options, other)}

  defp build(opts) do
    with {:ok, add} <- fetch_graph(opts, :add),
         {:ok, update} <- fetch_graph(opts, :update),
         {:ok, replace} <- fetch_graph(opts, :replace),
         {:ok, remove} <- fetch_graph(opts, :remove) do
      validate(%__MODULE__{add: add, update: update, replace: replace, remove: remove})
    end
  end

  # A non-`RDF.Graph` value is refused rather than raising a CaseClauseError.
  defp fetch_graph(opts, key) do
    case get(opts, key) do
      nil -> {:ok, nil}
      %Graph{} = graph -> {:ok, graph}
      other -> {:error, invalid_input(key, other)}
    end
  end

  defp get(opts, key) when is_list(opts), do: Keyword.get(opts, key)
  defp get(opts, key) when is_map(opts), do: Map.get(opts, key)

  defp invalid_input(key, value) do
    Refusal.new(
      :REFUSED_CHANGESET_CONFLICT,
      :mapping_changeset,
      "Changeset input #{inspect(key)} must be an RDF.Graph or nil",
      %{field: key, got: inspect(value)}
    )
  end

  @doc """
  Validates a changeset's mutual-exclusion invariants (ported from
  `Gno.Changeset.Validation`):

    * the same triple must not appear in both `:add` and `:remove`
    * the same subject must not be described in both `:update` and `:replace`

  Returns `{:ok, changeset}` on success, `{:error, %Refusal{}}` naming the
  conflicting subject/triple otherwise.
  """
  @spec validate(t()) :: {:ok, t()} | {:error, Refusal.t()}
  def validate(%__MODULE__{} = changeset) do
    with :ok <- validate_no_add_remove_overlap(changeset),
         :ok <- validate_no_update_replace_overlap(changeset) do
      {:ok, changeset}
    end
  end

  defp validate_no_add_remove_overlap(%__MODULE__{add: nil}), do: :ok
  defp validate_no_add_remove_overlap(%__MODULE__{remove: nil}), do: :ok

  defp validate_no_add_remove_overlap(%__MODULE__{add: add, remove: remove}) do
    overlap = GraphAlgebra.graph_intersection(add, remove)

    if Enum.empty?(overlap) do
      :ok
    else
      {:error,
       Refusal.new(
         :REFUSED_CHANGESET_CONFLICT,
         :mapping_changeset,
         "Triples present in both :add and :remove",
         %{overlapping_triple_count: Enum.count(overlap)}
       )}
    end
  end

  defp validate_no_update_replace_overlap(%__MODULE__{update: nil}), do: :ok
  defp validate_no_update_replace_overlap(%__MODULE__{replace: nil}), do: :ok

  defp validate_no_update_replace_overlap(%__MODULE__{update: update, replace: replace}) do
    update_subjects = update |> Graph.subjects() |> MapSet.new()
    replace_subjects = replace |> Graph.subjects() |> MapSet.new()
    overlap = MapSet.intersection(update_subjects, replace_subjects)

    if MapSet.size(overlap) == 0 do
      :ok
    else
      {:error,
       Refusal.new(
         :REFUSED_CHANGESET_CONFLICT,
         :mapping_changeset,
         "Subjects present in both :update and :replace",
         %{overlapping_subjects: MapSet.to_list(overlap)}
       )}
    end
  end

  @doc """
  Merges every action graph of `changeset` into a single graph of all
  statements it touches, regardless of action (add/update/replace/remove
  combined) -- the union Gno calls `merged_graph/1`.
  """
  @spec merged_graph(t()) :: Graph.t()
  def merged_graph(%__MODULE__{} = changeset) do
    @action_fields
    |> Enum.map(&Map.get(changeset, &1))
    |> union_or(Graph.new())
  end

  # Union of the non-nil graphs, or `empty` when there are none.
  defp union_or(graphs, empty) do
    case Enum.reject(graphs, &is_nil/1) do
      [] -> empty
      [first | rest] -> Enum.reduce(rest, first, &Graph.add(&2, &1))
    end
  end

  @doc """
  The graph of statements this changeset would insert if applied: `:add`,
  `:update`, and `:replace` all contribute new statements; `:remove` does not.
  """
  @spec inserts(t()) :: Graph.t()
  def inserts(%__MODULE__{} = changeset) do
    union_or([changeset.add, changeset.update, changeset.replace], Graph.new())
  end

  @doc "The graph of statements this changeset would remove if applied."
  @spec removals(t()) :: Graph.t()
  def removals(%__MODULE__{remove: nil}), do: Graph.new()
  def removals(%__MODULE__{remove: remove}), do: remove

  @doc """
  Inverts a changeset: what would undo its effect if applied on top of the
  result. `:add` becomes `:remove` and vice versa; `:update` and `:replace`
  fold into `:remove` (the caller must supply the prior state's statements to
  restore them -- inversion alone cannot recover data an update/replace
  overwrote, matching Gno's own documented limitation for these two actions).
  """
  @spec invert(t()) :: t()
  def invert(%__MODULE__{} = changeset) do
    folded_remove = union_or([changeset.add, changeset.update, changeset.replace], nil)

    %__MODULE__{
      add: changeset.remove,
      remove: folded_remove,
      update: nil,
      replace: nil
    }
  end

  @doc """
  Computes a pure add/remove changeset between two `RDF.Graph` snapshots:
  statements only in `new_graph` become `:add`; statements only in `old_graph`
  become `:remove`. Statements in both graphs are left out of the changeset
  entirely (unchanged). This is the store-independent replacement for Gno's
  `EffectiveChangeset.Query` SPARQL-CONSTRUCT diff -- both inputs are already
  in-memory graphs, so no store round-trip is needed.
  """
  @spec diff(Graph.t(), Graph.t()) :: {:ok, t()} | {:error, Refusal.t()}
  def diff(%Graph{} = old_graph, %Graph{} = new_graph) do
    added = GraphAlgebra.graph_delete(new_graph, old_graph)
    removed = GraphAlgebra.graph_delete(old_graph, new_graph)

    new(
      add: if(Enum.empty?(added), do: nil, else: added),
      remove: if(Enum.empty?(removed), do: nil, else: removed)
    )
  end

  @doc "True if the changeset has no statements in any action (a no-op diff)."
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{} = changeset) do
    @action_fields
    |> Enum.map(&Map.get(changeset, &1))
    |> Enum.all?(&(is_nil(&1) or Enum.empty?(&1)))
  end
end
