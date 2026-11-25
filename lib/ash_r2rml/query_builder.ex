# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.QueryBuilder do
  @moduledoc """
  Pure builder from a normalized mapping and a `AshR2RML.QueryBuilder.Plan` to an `Ash.Query`.

  The query selects only subject-identity attributes (template fields / primary key) plus
  `plan.needed_attributes`, never an attribute marked `sensitive?: true`; loads only
  `plan.needed_relationships`; pushes the filter down as an `Ash.Expr`; and bounds the read to
  `min(plan.limit, max_rows + 1)` so a caller can detect an exceeded row bound (fail closed)
  by seeing more than `max_rows` rows.

  Nothing is executed here: the caller runs `Ash.read/2` on the returned query.

  Collaborators live beside this file: `AshR2RML.QueryBuilder.Plan` (input),
  `AshR2RML.QueryBuilder.Modifiers` (ORDER BY / LIMIT / OFFSET), `AshR2RML.QueryBuilder.Lowering`
  (SPARQL to pushdown) and `AshR2RML.QueryBuilder.Verification` (post-read soundness check).
  """

  require Ash.Expr
  require Ash.Query

  alias AshR2RML.Mapping
  alias AshR2RML.Capability
  alias AshR2RML.Mapping.{Resource, SubjectMap}
  alias AshR2RML.QueryBuilder.Plan
  alias AshR2RML.Refusal

  @default_max_rows 10_000

  @doc """
  Builds the `%Ash.Query{}` for `plan` over `mapping.ash_resource`.

  Options: `:actor`, `:tenant`, `:domain`, `:action` (default: primary read), `:max_rows`
  (default #{@default_max_rows}), `:authorize?` (default `true`), `:row_cap` (optional extra
  limit ceiling, see `triple_row_cap/2`; it only ever lowers the limit).

  Returns `{:error, %AshR2RML.Refusal{}}` (fail closed) for an unknown or sensitive attribute,
  an unknown relationship, a malformed filter, or a resource without a read action.
  """
  @spec build_ash_query(Resource.t(), Plan.t(), keyword()) :: Ash.Query.t() | {:error, Refusal.t()}
  def build_ash_query(%Resource{ash_resource: resource} = mapping, %Plan{} = plan, opts \\ [])
      when is_atom(resource) do
    max_rows = Keyword.get(opts, :max_rows, @default_max_rows)

    with {:ok, action} <- read_action(mapping, opts),
         :ok <- check_attributes(mapping, plan.needed_attributes),
         :ok <- check_relationships(mapping, plan.needed_relationships),
         {:ok, sort_attrs} <- sort_attributes(mapping, plan.sort),
         {:ok, filter_attrs} <- filter_attributes(mapping, plan.filter),
         :ok <- check_attributes(mapping, filter_attrs ++ sort_attrs),
         :ok <- check_field_policy(mapping, filter_attrs ++ sort_attrs),
         {:ok, filter_expr} <- filter_expr(mapping, plan.filter) do
      select = select_attributes(mapping, plan)
      caps = Capability.probe(resource)

      # A sorted/offset window is only meaningful when every part of it is pushed: a limit
      # without its sort (or offset) would drop rows, so the whole window is skipped instead.
      window? =
        (plan.sort == [] or caps.sort) and (plan.offset in [nil, 0] or caps.offset)

      # Without a window the plan limit is not pushed, but the row bound (max_rows / row_cap)
      # still applies so an exceeded bound is detectable.
      limit_value = if window?, do: plan.limit, else: nil

      resource
      |> Ash.Query.new()
      |> Ash.Query.for_read(action, %{}, read_opts(opts))
      |> Ash.Query.select(select)
      |> maybe_load(plan.needed_relationships)
      |> maybe_filter(if(caps.filter, do: filter_expr))
      |> maybe_sort(if(window?, do: plan.sort, else: []))
      |> maybe_offset(if(window?, do: plan.offset))
      |> maybe_limit(caps.limit, clamp_row_cap(effective_limit(limit_value, max_rows), opts[:row_cap]))
    end
  end

  defp clamp_row_cap(limit, cap) when is_integer(cap) and cap > 0, do: min(limit, cap)
  defp clamp_row_cap(limit, _cap), do: limit

  @doc """
  Smallest row count that provably exceeds a triple budget: every row emits at least
  `min_per_row` triples, so `div(budget, min_per_row) + 1` rows cannot fit. `nil` when no
  clamp is provable (`min_per_row` of 0 or a non-integer budget).

  Pass the result as the `:row_cap` option of `build_ash_query/3` / `pushdown_query/4`; a read
  returning `row_cap` rows is then a proof of `REFUSED_TRIPLE_LIMIT_EXCEEDED`.

      iex> AshR2RML.QueryBuilder.triple_row_cap(100, 4)
      26
      iex> AshR2RML.QueryBuilder.triple_row_cap(100, 0)
      nil
      iex> AshR2RML.QueryBuilder.triple_row_cap(nil, 3)
      nil
  """
  @spec triple_row_cap(integer() | nil, non_neg_integer()) :: pos_integer() | nil
  def triple_row_cap(budget, min_per_row) when is_integer(budget) and is_integer(min_per_row) and min_per_row > 0,
    do: div(max(budget, 0), min_per_row) + 1

  def triple_row_cap(_budget, _min_per_row), do: nil

  defp maybe_limit(query, true, limit), do: Ash.Query.limit(query, limit)
  defp maybe_limit(query, false, _limit), do: query

  @doc """
  Pure builder for the ROOT-resource read of a SPARQL pushdown (see
  `AshR2RML.QueryBuilder.Lowering.lower/3`). Equivalent to `build_ash_query/3` with the mapping
  bound to `resource`; the returned query already carries filter, sort and a limit bounded by
  `min(plan.limit, max_rows + 1)`, so the receiver must not re-apply its own limit.

  Returns `{:error, %AshR2RML.Refusal{}}` when the plan is not admissible; the receiver then
  reads without pushdown.
  """
  @spec pushdown_query(module(), Resource.t(), Plan.t(), keyword()) :: Ash.Query.t() | {:error, Refusal.t()}
  def pushdown_query(resource, %Resource{} = mapping, %Plan{} = plan, opts \\ []) when is_atom(resource),
    do: build_ash_query(%Resource{mapping | ash_resource: resource}, plan, opts)

  @doc "Lowers a SPARQL SELECT to a root-resource pushdown; see `AshR2RML.QueryBuilder.Lowering`."
  @spec lower(String.t(), [{module(), Resource.t()}], keyword()) ::
          {:ok, AshR2RML.QueryBuilder.Pushdown.t()} | :fallback
  def lower(sparql, specs, opts \\ []), do: AshR2RML.QueryBuilder.Lowering.lower(sparql, specs, opts)

  @doc "Post-read soundness check of a limited pushdown; see `AshR2RML.QueryBuilder.Verification`."
  @spec verify(AshR2RML.QueryBuilder.Pushdown.t(), RDF.Graph.t(), non_neg_integer()) :: :ok | :fallback
  def verify(pushdown, graph, solution_count),
    do: AshR2RML.QueryBuilder.Verification.verify(pushdown, graph, solution_count)

  @doc """
  Row bound applied to a read: `min(limit, max_rows + 1)`; `nil` limit means `max_rows + 1`.

      iex> AshR2RML.QueryBuilder.effective_limit(nil, 10)
      11
      iex> AshR2RML.QueryBuilder.effective_limit(3, 10)
      3
      iex> AshR2RML.QueryBuilder.effective_limit(50, 10)
      11
  """
  @spec effective_limit(non_neg_integer() | nil, pos_integer()) :: pos_integer() | 0
  def effective_limit(nil, max_rows), do: max_rows + 1
  def effective_limit(limit, max_rows) when is_integer(limit), do: min(limit, max_rows + 1)

  # -- options / action ------------------------------------------------------------------

  defp read_opts(opts) do
    base = [authorize?: Keyword.get(opts, :authorize?) != false]

    Enum.reduce([:actor, :tenant, :domain, :context, :scope], base, fn key, acc ->
      case Keyword.get(opts, key) do
        nil -> acc
        value -> [{key, value} | acc]
      end
    end)
  end

  defp read_action(%Resource{ash_resource: resource} = mapping, opts) do
    case opts[:action] || primary_read(resource) do
      nil ->
        {:error, refuse(mapping, :REFUSED_INVALID_TERM_MAP, "resource has no read action", %{})}

      action ->
        {:ok, action}
    end
  end

  defp primary_read(resource) do
    case Ash.Resource.Info.primary_action(resource, :read) do
      %{name: name} -> name
      _ -> nil
    end
  end

  # -- validation ------------------------------------------------------------------------

  defp check_attributes(mapping, names), do: check_each(mapping, names, &admit_attribute/2)

  # A malformed sort entry (wrong shape or direction) refuses instead of crashing in `elem/2`
  # or inside `Ash.Query.sort/2`.
  defp sort_attributes(mapping, sort) when is_list(sort) do
    Enum.reduce_while(sort, {:ok, []}, fn
      {attribute, direction}, {:ok, acc} when is_atom(attribute) and direction in [:asc, :desc] ->
        {:cont, {:ok, acc ++ [attribute]}}

      other, _acc ->
        {:halt, bad_sort(mapping, other)}
    end)
  end

  defp sort_attributes(mapping, other), do: bad_sort(mapping, other)

  defp bad_sort(mapping, other) do
    detail = "unsupported sort shape"
    {:error, refuse(mapping, :REFUSED_UNSUPPORTED_SPARQL_FEATURE, detail, %{sort: inspect(other)})}
  end

  # A field-policy-gated attribute must never be filtered or sorted in the data layer: the
  # surviving row set would be an oracle on the hidden value.
  defp check_field_policy(%Resource{ash_resource: resource} = mapping, names) do
    check_each(mapping, Enum.uniq(names), fn _mapping, name ->
      if AshR2RML.Security.field_policy_protected?(resource, name) do
        {:error,
         refuse(
           mapping,
           :REFUSED_SENSITIVE_ATTRIBUTE_MATERIALIZATION,
           "field-policy-protected attribute is not admitted for filter or sort",
           %{attribute: name}
         )}
      else
        :ok
      end
    end)
  end

  defp check_each(mapping, names, fun) do
    Enum.reduce_while(names, :ok, fn name, :ok ->
      case fun.(mapping, name) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp admit_attribute(%Resource{ash_resource: resource} = mapping, name) do
    case Ash.Resource.Info.attribute(resource, name) do
      nil ->
        {:error, refuse(mapping, :REFUSED_UNKNOWN_ATTRIBUTE, "attribute is not on the resource", %{attribute: name})}

      %{sensitive?: true} ->
        {:error,
         refuse(
           mapping,
           :REFUSED_SENSITIVE_ATTRIBUTE_MATERIALIZATION,
           "sensitive attribute is not admitted for select, filter or sort",
           %{attribute: name}
         )}

      _ ->
        :ok
    end
  end

  defp check_relationships(%Resource{ash_resource: resource} = mapping, names) do
    check_each(mapping, names, fn _mapping, name ->
      if Ash.Resource.Info.relationship(resource, name) do
        :ok
      else
        {:error,
         refuse(mapping, :REFUSED_AMBIGUOUS_RELATIONSHIP, "relationship is not on the resource", %{
           relationship: name
         })}
      end
    end)
  end

  # -- select ----------------------------------------------------------------------------

  defp select_attributes(%Resource{ash_resource: resource} = mapping, %Plan{} = plan) do
    relationship_keys =
      for name <- plan.needed_relationships,
          rel = Ash.Resource.Info.relationship(resource, name),
          do: rel.source_attribute

    (subject_attributes(mapping) ++
       Ash.Resource.Info.primary_key(resource) ++ relationship_keys ++ plan.needed_attributes)
    |> Enum.uniq()
    |> Enum.filter(&selectable?(resource, &1))
  end

  defp selectable?(resource, name) do
    case Ash.Resource.Info.attribute(resource, name) do
      nil -> false
      %{sensitive?: true} -> false
      _ -> true
    end
  end

  defp subject_attributes(%Resource{ash_resource: resource, subject_map: %SubjectMap{} = subject}) do
    for field <- subject_fields(subject),
        attribute <- Ash.Resource.Info.attributes(resource),
        Atom.to_string(attribute.name) == field,
        do: attribute.name
  end

  defp subject_attributes(_), do: []

  defp subject_fields(%SubjectMap{strategy: :template, value: value}), do: Mapping.template_fields(value)
  defp subject_fields(%SubjectMap{strategy: :column, value: value}), do: [value]
  defp subject_fields(%SubjectMap{}), do: []

  # -- load / sort / paging --------------------------------------------------------------

  defp maybe_load(query, []), do: query
  defp maybe_load(query, names), do: Ash.Query.load(query, Enum.uniq(names))

  defp maybe_filter(query, nil), do: query
  defp maybe_filter(query, expression), do: Ash.Query.filter(query, ^expression)

  defp maybe_sort(query, []), do: query
  defp maybe_sort(query, sort), do: Ash.Query.sort(query, sort)

  defp maybe_offset(query, offset) when is_integer(offset) and offset > 0,
    do: Ash.Query.offset(query, offset)

  defp maybe_offset(query, _), do: query

  # -- filter pushdown -------------------------------------------------------------------

  @ops [:eq, :neq, :lt, :lte, :gt, :gte, :contains, :strstarts, :strends, :not_nil]

  defp filter_attributes(_mapping, nil), do: {:ok, []}

  defp filter_attributes(mapping, {combinator, filters}) when combinator in [:and, :or] and is_list(filters) do
    Enum.reduce_while(filters, {:ok, []}, fn filter, {:ok, acc} ->
      case filter_attributes(mapping, filter) do
        {:ok, attrs} -> {:cont, {:ok, acc ++ attrs}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp filter_attributes(_mapping, {op, attribute, _value}) when op in @ops and is_atom(attribute),
    do: {:ok, [attribute]}

  defp filter_attributes(mapping, other),
    do:
      {:error,
       refuse(mapping, :REFUSED_UNSUPPORTED_SPARQL_FEATURE, "unsupported filter shape", %{filter: inspect(other)})}

  defp filter_expr(_mapping, nil), do: {:ok, nil}

  defp filter_expr(mapping, {combinator, filters}) when combinator in [:and, :or] do
    filters
    |> Enum.reduce_while({:ok, []}, fn filter, {:ok, acc} ->
      case filter_expr(mapping, filter) do
        {:ok, expression} -> {:cont, {:ok, [expression | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, []} -> {:ok, nil}
      {:ok, expressions} -> {:ok, expressions |> Enum.reverse() |> combine(combinator)}
      {:error, _} = error -> error
    end
  end

  defp filter_expr(_mapping, {op, attribute, value}), do: {:ok, comparison(op, Ash.Expr.ref(attribute), value)}

  defp combine([first | rest], :and),
    do: Enum.reduce(rest, first, fn right, left -> Ash.Expr.expr(^left and ^right) end)

  defp combine([first | rest], :or),
    do: Enum.reduce(rest, first, fn right, left -> Ash.Expr.expr(^left or ^right) end)

  defp comparison(:not_nil, ref, _value), do: Ash.Expr.expr(not is_nil(^ref))
  defp comparison(:eq, ref, value), do: Ash.Expr.expr(^ref == ^value)
  defp comparison(:neq, ref, value), do: Ash.Expr.expr(^ref != ^value)
  defp comparison(:lt, ref, value), do: Ash.Expr.expr(^ref < ^value)
  defp comparison(:lte, ref, value), do: Ash.Expr.expr(^ref <= ^value)
  defp comparison(:gt, ref, value), do: Ash.Expr.expr(^ref > ^value)
  defp comparison(:gte, ref, value), do: Ash.Expr.expr(^ref >= ^value)
  defp comparison(:contains, ref, value), do: Ash.Expr.expr(contains(^ref, ^value))
  defp comparison(:strstarts, ref, value), do: Ash.Expr.expr(string_starts_with(^ref, ^value))
  defp comparison(:strends, ref, value), do: Ash.Expr.expr(string_ends_with(^ref, ^value))

  defp refuse(%Resource{ash_resource: subject}, code, detail, evidence),
    do: Refusal.new(code, subject, detail, evidence)
end
