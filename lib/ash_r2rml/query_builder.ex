# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.QueryBuilder.Plan do
  @moduledoc """
  Query plan consumed by `AshR2RML.QueryBuilder.build_ash_query/3`.

  Filter grammar (all attribute names are atoms):

    * `{op, attribute, value}` with `op` in `:eq | :neq | :lt | :lte | :gt | :gte |
      :contains | :strstarts | :strends`
    * `{:and, [filter]}` / `{:or, [filter]}`
    * `nil` (no filter)

  `sort` is a list of `{attribute, :asc | :desc}`.
  """

  defstruct needed_attributes: [],
            needed_relationships: [],
            filter: nil,
            sort: [],
            offset: 0,
            limit: nil

  @type op :: :eq | :neq | :lt | :lte | :gt | :gte | :contains | :strstarts | :strends
  @type filter ::
          nil
          | {op(), atom(), term()}
          | {:and, [filter()]}
          | {:or, [filter()]}

  @type t :: %__MODULE__{
          needed_attributes: [atom()],
          needed_relationships: [atom()],
          filter: filter(),
          sort: [{atom(), :asc | :desc}],
          offset: non_neg_integer(),
          limit: pos_integer() | nil
        }
end

defmodule AshR2RML.QueryBuilder do
  @moduledoc """
  Pure builder from a normalized mapping and a `AshR2RML.QueryBuilder.Plan` to an `Ash.Query`.

  The query selects only subject-identity attributes (template fields / primary key) plus
  `plan.needed_attributes`, never an attribute marked `sensitive?: true`; loads only
  `plan.needed_relationships`; pushes the filter down as an `Ash.Expr`; and bounds the read to
  `min(plan.limit, max_rows + 1)` so a caller can detect an exceeded row bound (fail closed)
  by seeing more than `max_rows` rows.

  Nothing is executed here: the caller runs `Ash.read/2` on the returned query.
  """

  require Ash.Expr
  require Ash.Query

  alias AshR2RML.Mapping
  alias AshR2RML.Mapping.{Resource, SubjectMap}
  alias AshR2RML.QueryBuilder.Plan
  alias AshR2RML.Refusal

  @default_max_rows 10_000

  @doc """
  Builds the `%Ash.Query{}` for `plan` over `mapping.ash_resource`.

  Options: `:actor`, `:tenant`, `:domain`, `:action` (default: primary read), `:max_rows`
  (default #{@default_max_rows}), `:authorize?` (default `true`).

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
         {:ok, filter_attrs} <- filter_attributes(mapping, plan.filter),
         :ok <- check_filterable(mapping, filter_attrs ++ Enum.map(plan.sort, &elem(&1, 0))),
         {:ok, filter_expr} <- filter_expr(mapping, plan.filter) do
      select = select_attributes(mapping, plan)

      resource
      |> Ash.Query.new()
      |> maybe_tenant(opts[:tenant])
      |> Ash.Query.for_read(action, %{}, read_opts(opts))
      |> Ash.Query.select(select)
      |> maybe_load(plan.needed_relationships)
      |> maybe_filter(filter_expr)
      |> maybe_sort(plan.sort)
      |> maybe_offset(plan.offset)
      |> Ash.Query.limit(effective_limit(plan.limit, max_rows))
    end
  end

  @doc """
  Row bound applied to a read: `min(limit, max_rows + 1)`; `nil` limit means `max_rows + 1`.

      iex> AshR2RML.QueryBuilder.effective_limit(nil, 10)
      11
      iex> AshR2RML.QueryBuilder.effective_limit(3, 10)
      3
      iex> AshR2RML.QueryBuilder.effective_limit(50, 10)
      11
  """
  @spec effective_limit(pos_integer() | nil, pos_integer()) :: pos_integer()
  def effective_limit(nil, max_rows), do: max_rows + 1
  def effective_limit(limit, max_rows) when is_integer(limit), do: min(limit, max_rows + 1)

  # -- options / action ------------------------------------------------------------------

  defp read_opts(opts) do
    base = [authorize?: Keyword.get(opts, :authorize?, true)]

    Enum.reduce([:actor, :tenant, :domain], base, fn key, acc ->
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

  defp check_filterable(mapping, names), do: check_each(mapping, names, &admit_attribute/2)

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
    fields =
      case subject.strategy do
        :template -> Mapping.template_fields(subject.value)
        :column -> [subject.value]
        _ -> []
      end

    for field <- fields,
        attribute <- Ash.Resource.Info.attributes(resource),
        Atom.to_string(attribute.name) == field,
        do: attribute.name
  end

  defp subject_attributes(_), do: []

  # -- load / sort / paging --------------------------------------------------------------

  defp maybe_tenant(query, nil), do: query
  defp maybe_tenant(query, tenant), do: Ash.Query.set_tenant(query, tenant)

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

  @ops [:eq, :neq, :lt, :lte, :gt, :gte, :contains, :strstarts, :strends]

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
