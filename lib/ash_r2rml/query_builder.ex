# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.QueryBuilder.Plan do
  @moduledoc """
  Query plan consumed by `AshR2RML.QueryBuilder.build_ash_query/3`.

  Filter grammar (all attribute names are atoms):

    * `{op, attribute, value}` with `op` in `:eq | :neq | :lt | :lte | :gt | :gte |
      :contains | :strstarts | :strends`
    * `{:not_nil, attribute, nil}` (attribute is not null)
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

  @type op :: :eq | :neq | :lt | :lte | :gt | :gte | :contains | :strstarts | :strends | :not_nil
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

defmodule AshR2RML.QueryBuilder.Modifiers do
  @moduledoc """
  SPARQL solution modifiers (`ORDER BY`, `LIMIT`, `OFFSET`) parsed from the query text and
  applied to projected binding rows.

  SPARQL.ex does not implement these modifiers, so `AshR2RML.OBDA` applies them itself.
  Parsing is deliberately strict: a tail it cannot fully account for (`GROUP BY`, `HAVING`,
  `VALUES`, `ORDER BY` over a function call) yields `:unparsed` and the rows are left untouched.

  ## Examples

      iex> AshR2RML.QueryBuilder.Modifiers.parse("SELECT ?x WHERE { ?s ?p ?x } ORDER BY DESC(?x) ?s LIMIT 5 OFFSET 2")
      {:ok, %{order: [{"x", :desc}, {"s", :asc}], limit: 5, offset: 2}}

      iex> AshR2RML.QueryBuilder.Modifiers.parse("SELECT ?x WHERE { ?s ?p ?x }")
      {:ok, %{order: [], limit: nil, offset: 0}}

      iex> AshR2RML.QueryBuilder.Modifiers.parse("SELECT ?x WHERE { ?s ?p ?x } GROUP BY ?x")
      :unparsed

      iex> rows = [%{"x" => 1}, %{"x" => 3}, %{"x" => 2}]
      iex> AshR2RML.QueryBuilder.Modifiers.run(rows, {:ok, %{order: [{"x", :desc}], limit: 2, offset: 0}})
      [%{"x" => 3}, %{"x" => 2}]
  """

  @type direction :: :asc | :desc
  @type t :: %{order: [{String.t(), direction()}], limit: non_neg_integer() | nil, offset: non_neg_integer()}

  @cond_regex ~r/(ASC|DESC)\s*\(\s*\?(\w+)\s*\)|\?(\w+)/i

  @doc "Parses the solution-modifier tail of `sparql`."
  @spec parse(String.t()) :: {:ok, t()} | :unparsed
  def parse(sparql) when is_binary(sparql) do
    case tail(sparql) do
      nil ->
        :unparsed

      tail ->
        {order_src, rest} = split_order(tail)
        {limit, rest} = take_int(rest, ~r/\bLIMIT\s+(\d+)/i)
        {offset, rest} = take_int(rest, ~r/\bOFFSET\s+(\d+)/i)

        with true <- String.trim(rest) == "",
             {:ok, order} <- parse_order(order_src) do
          {:ok, %{order: order, limit: limit, offset: offset || 0}}
        else
          _ -> :unparsed
        end
    end
  end

  @doc "Applies parsed modifiers to binding rows: ORDER BY, then OFFSET, then LIMIT."
  @spec run([map()], {:ok, t()} | :unparsed) :: [map()]
  def run(rows, {:ok, %{order: order, limit: limit, offset: offset}}) when is_list(rows) do
    rows
    |> sort(order)
    |> Enum.drop(offset)
    |> then(fn rows -> if limit, do: Enum.take(rows, limit), else: rows end)
  end

  def run(rows, _unparsed), do: rows

  @doc """
  Total order over normalized binding values: unbound first, then numbers (numeric), then
  strings (bytewise), then anything else by `inspect/1`.
  """
  @spec compare(term(), term()) :: :lt | :eq | :gt
  def compare(a, b) when a == b, do: :eq
  def compare(nil, _), do: :lt
  def compare(_, nil), do: :gt
  def compare(a, b) when is_number(a) and is_number(b), do: if(a < b, do: :lt, else: :gt)
  def compare(%Decimal{} = a, b) when is_number(b) or is_struct(b, Decimal), do: Decimal.compare(a, to_decimal(b))
  def compare(a, %Decimal{} = b) when is_number(a), do: Decimal.compare(to_decimal(a), b)
  def compare(a, b) when is_binary(a) and is_binary(b), do: if(a < b, do: :lt, else: :gt)

  def compare(a, b) do
    case {rank(a), rank(b)} do
      {same, same} -> if inspect(a) < inspect(b), do: :lt, else: :gt
      {ra, rb} -> if ra < rb, do: :lt, else: :gt
    end
  end

  defp rank(v) when is_number(v) or is_struct(v, Decimal), do: 0
  defp rank(v) when is_binary(v), do: 1
  defp rank(_), do: 2

  defp to_decimal(%Decimal{} = d), do: d
  defp to_decimal(n) when is_integer(n), do: Decimal.new(n)
  defp to_decimal(n) when is_float(n), do: Decimal.from_float(n)

  defp sort(rows, []), do: rows

  defp sort(rows, order) do
    # An ORDER BY variable that is not projected is absent from every row; it cannot be applied.
    order = Enum.filter(order, fn {var, _dir} -> Enum.any?(rows, &Map.has_key?(&1, var)) end)

    case order do
      [] -> rows
      _ -> Enum.sort(rows, fn a, b -> compare_rows(a, b, order) != :gt end)
    end
  end

  defp compare_rows(a, b, order) do
    Enum.reduce_while(order, :eq, fn {var, dir}, :eq ->
      case compare(Map.get(a, var), Map.get(b, var)) do
        :eq -> {:cont, :eq}
        result -> {:halt, if(dir == :desc, do: flip(result), else: result)}
      end
    end)
  end

  defp flip(:lt), do: :gt
  defp flip(:gt), do: :lt

  # Text after the last closing brace, with IRIs, string literals and comments removed so a
  # brace inside any of them cannot move the split point.
  defp tail(sparql) do
    stripped =
      sparql
      |> String.replace(~r/<[^<>"{}|^`\\\s]*>/, "<I>")
      |> String.replace(~r/"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'/s, "\"S\"")
      |> String.replace(~r/#[^\n]*/, "")

    case :binary.matches(stripped, "}") do
      [] ->
        nil

      matches ->
        {pos, 1} = List.last(matches)
        binary_part(stripped, pos + 1, byte_size(stripped) - pos - 1)
    end
  end

  defp split_order(tail) do
    case Regex.run(~r/\bORDER\s+BY\b(.*?)(?=\bLIMIT\b|\bOFFSET\b|\z)/is, tail) do
      [whole, conds] -> {conds, String.replace(tail, whole, "", global: false)}
      nil -> {nil, tail}
    end
  end

  defp take_int(text, regex) do
    case Regex.run(regex, text) do
      [whole, n] -> {String.to_integer(n), String.replace(text, whole, "", global: false)}
      nil -> {nil, text}
    end
  end

  defp parse_order(nil), do: {:ok, []}

  defp parse_order(src) do
    conds = Regex.scan(@cond_regex, src)
    leftover = Regex.replace(@cond_regex, src, "")

    if conds == [] or String.trim(leftover) != "" do
      :error
    else
      {:ok,
       Enum.map(conds, fn
         [_, dir, var] -> {var, direction(dir)}
         [_, _, _, var] -> {var, :asc}
       end)}
    end
  end

  defp direction(dir), do: if(String.upcase(dir) == "DESC", do: :desc, else: :asc)
end

defmodule AshR2RML.QueryBuilder.Pushdown do
  @moduledoc """
  A lowered SPARQL SELECT: the root resource, its mapping and the `AshR2RML.QueryBuilder.Plan`
  to read it with, plus the data `AshR2RML.QueryBuilder.Lowering.verify/3` needs when the plan
  carries a limit.

  `keep` is `offset + limit` and `fetch` is `keep + 1` (the extra row is a tie sentinel); both
  are `nil` when the plan has no limit.
  """

  alias AshR2RML.Mapping.Resource
  alias AshR2RML.QueryBuilder.Plan

  @enforce_keys [:resource, :mapping, :plan]
  defstruct [:resource, :mapping, :plan, :keep, :fetch, keys: []]

  @type t :: %__MODULE__{
          resource: module(),
          mapping: Resource.t(),
          plan: Plan.t(),
          keep: pos_integer() | nil,
          fetch: pos_integer() | nil,
          keys: [map()]
        }

  @doc """
  The value of the `:query_pushdown` read option understood by `AshR2RML.OBDA.InMemory`.

  Only the spec whose `ash_resource == resource` is read through
  `AshR2RML.QueryBuilder.pushdown_query/4`; every other spec reads as before.
  """
  @spec read_option(t()) :: %{resource: module(), mapping: Resource.t(), plan: Plan.t()}
  def read_option(%__MODULE__{resource: resource, mapping: mapping, plan: plan}),
    do: %{resource: resource, mapping: mapping, plan: plan}
end

defmodule AshR2RML.QueryBuilder.Lowering do
  @moduledoc """
  Lowers a SPARQL SELECT to a pushdown for ONE root resource, or `:fallback` whenever any part
  of the query is not provably safe to narrow.

  Admitted shape: a single basic graph pattern (optionally with FILTER) whose root subject
  variable is a star over exactly one spec's predicates (attribute predicates and
  `reference_object_maps`), optionally joined through a reference object map to further
  subjects. OPTIONAL, UNION, MINUS, aggregates, DISTINCT, subqueries, constant objects,
  variable predicates and blank nodes all fall back.

  What is pushed to the root read:

    * `not is_nil` for every star attribute and subject-template field (a row with a null there
      yields no triple, hence no solution: exact),
    * each top-level conjunct of FILTER that compares a root attribute (`= != < <= > >=`, mapped
      integer / decimal / string column, matching constant); other conjuncts are left to
      SPARQL.ex, which re-applies every FILTER over the narrowed graph,
    * ORDER BY + LIMIT/OFFSET only when ordered by star attributes of kind integer or string
      (string ordering only on `Ash.DataLayer.Ets`), the resource has no authorizer and a
      template subject, as `sort` plus `limit = offset + limit + 1`. `verify/3` then proves, from
      the materialized graph, that the narrowed read cannot have dropped a solution (join
      starvation, tie at the boundary, untyped literals) and otherwise requests a full re-read.

  A root resource that is also a join parent of any spec is never narrowed.
  """

  alias AshR2RML.Mapping
  alias AshR2RML.Mapping.{Datatype, ObjectMap, ReferenceObjectMap, Resource, SubjectMap}
  alias AshR2RML.QueryBuilder.{Modifiers, Plan, Pushdown}
  alias AshR2RML.SPARQL.Query, as: Admitted
  alias SPARQL.Algebra.{BGP, Filter, FunctionCall, Project}

  @xsd "http://www.w3.org/2001/XMLSchema#"
  @xsd_integer @xsd <> "integer"
  @xsd_decimal @xsd <> "decimal"
  @xsd_string @xsd <> "string"

  @ops %{=: :eq, !=: :neq, <: :lt, <=: :lte, >: :gt, >=: :gte}
  @flip %{eq: :eq, neq: :neq, lt: :gt, lte: :gte, gt: :lt, gte: :lte}

  @doc "Lowers `sparql` against `specs` (`{ash_resource, %Mapping.Resource{}}` pairs)."
  @spec lower(String.t(), [{module(), Resource.t()}], keyword()) :: {:ok, Pushdown.t()} | :fallback
  def lower(sparql, specs, _opts \\ []) when is_binary(sparql) and is_list(specs) do
    do_lower(sparql, specs)
  rescue
    _ -> :fallback
  end

  defp do_lower(sparql, specs) do
    with {:ok, admitted} <- Admitted.admit(sparql),
         :select <- admitted.form,
         {:ok, triples, filters} <- body(admitted.parsed.expr),
         true <- Enum.all?(triples, &simple_triple?/1),
         {:ok, root_triples, others} <- root_star(triples),
         {:ok, resource, mapping} <- root_spec(root_triples, specs),
         {:ok, infos} <- classify(root_triples, resource, mapping),
         true <- others_ok?(others, infos),
         {:ok, subject_attrs} <- subject_attributes(resource, mapping) do
      assemble(sparql, resource, mapping, filters, infos, subject_attrs)
    else
      _ -> :fallback
    end
  end

  # -- algebra ---------------------------------------------------------------------------

  defp body(%Project{expr: expr}), do: body_inner(expr)
  defp body(expr), do: body_inner(expr)

  defp body_inner(%Filter{filters: filters, expr: %BGP{triples: [_ | _] = triples}}) when is_list(filters),
    do: {:ok, triples, filters}

  defp body_inner(%BGP{triples: [_ | _] = triples}), do: {:ok, triples, []}
  defp body_inner(_), do: :error

  defp simple_triple?({s, %RDF.IRI{}, o}) when is_binary(s) and is_binary(o), do: true
  defp simple_triple?(_), do: false

  defp pred({_s, %RDF.IRI{} = p, _o}), do: RDF.IRI.to_string(p)

  defp root_star(triples) do
    subjects = triples |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
    objects = Enum.map(triples, &elem(&1, 2))

    with true <- length(objects) == length(Enum.uniq(objects)),
         [root] <- Enum.reject(subjects, &(&1 in objects)) do
      {:ok, Enum.filter(triples, &(elem(&1, 0) == root)), subjects -- [root]}
    else
      _ -> :error
    end
  end

  # -- root spec -------------------------------------------------------------------------

  defp root_spec(root_triples, specs) do
    preds = Enum.map(root_triples, &pred/1)

    candidates =
      Enum.filter(specs, fn {_resource, mapping} ->
        provided = provided_predicates(mapping)
        Enum.all?(preds, &(&1 in provided))
      end)

    with true <- length(preds) == length(Enum.uniq(preds)),
         [{resource, mapping}] <- candidates,
         false <- referenced_parent?(specs, resource),
         true <- unique_subject_template?(specs, mapping) do
      {:ok, resource, mapping}
    else
      _ -> :error
    end
  end

  defp provided_predicates(%Resource{} = mapping) do
    for(pom <- mapping.predicate_object_maps || [], pom.attribute != nil, do: pom.predicate_iri) ++
      for ref <- mapping.reference_object_maps || [], do: ref.predicate_iri
  end

  defp referenced_parent?(specs, resource) do
    Enum.any?(specs, fn {_r, mapping} ->
      Enum.any?(mapping.reference_object_maps || [], &(&1.parent_resource == resource))
    end)
  end

  defp unique_subject_template?(specs, %Resource{subject_map: %SubjectMap{value: value}}),
    do: Enum.count(specs, fn {_r, m} -> match?(%SubjectMap{value: ^value}, m.subject_map) end) == 1

  defp unique_subject_template?(_specs, _mapping), do: false

  # -- star classification ---------------------------------------------------------------

  defp classify(root_triples, resource, mapping) do
    Enum.reduce_while(root_triples, {:ok, []}, fn {_s, _p, var} = triple, {:ok, acc} ->
      predicate = pred(triple)
      poms = Enum.filter(mapping.predicate_object_maps || [], &(&1.predicate_iri == predicate))
      refs = Enum.filter(mapping.reference_object_maps || [], &(&1.predicate_iri == predicate))

      result =
        case {poms, refs} do
          {[pom], []} -> attribute_info(pom, var, predicate, resource)
          {[], [ref]} -> reference_info(ref, var, predicate, resource)
          _ -> :error
        end

      case result do
        {:ok, info} -> {:cont, {:ok, [info | acc]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, infos} -> {:ok, Enum.reverse(infos)}
      :error -> :error
    end
  end

  defp attribute_info(pom, var, predicate, resource) do
    attribute = pom.attribute

    with true <- is_atom(attribute) and not is_nil(attribute),
         %ObjectMap{strategy: :column, term_type: :literal, language: nil} = om <- pom.object_map,
         true <- om.graph_maps in [nil, []] and pom.graph_maps in [nil, []],
         true <- to_string(om.value) == Atom.to_string(attribute),
         {:ok, declared} <- declared_datatype(om.datatype),
         %{sensitive?: false} = ash_attr <- Ash.Resource.Info.attribute(resource, attribute) do
      kind = kind(declared, ash_attr.type)

      {:ok,
       %{
         type: :attr,
         var: var,
         predicate: predicate,
         attribute: attribute,
         kind: kind,
         datatype: declared || default_datatype(kind)
       }}
    else
      _ -> :error
    end
  end

  defp declared_datatype(nil), do: {:ok, nil}

  defp declared_datatype(%Datatype{lexical_encoder: nil, storage_type: nil, rdf_datatype: iri})
       when is_binary(iri) or is_nil(iri),
       do: {:ok, iri}

  defp declared_datatype(_), do: :error

  defp kind(declared, ash_type) do
    ash_kind =
      case ash_type do
        Ash.Type.Integer -> :integer
        Ash.Type.String -> :string
        Ash.Type.Decimal -> :decimal
        _ -> :other
      end

    if declared in [nil, default_datatype(ash_kind)], do: ash_kind, else: :other
  end

  defp default_datatype(:integer), do: @xsd_integer
  defp default_datatype(:decimal), do: @xsd_decimal
  defp default_datatype(:string), do: @xsd_string
  defp default_datatype(_), do: nil

  defp reference_info(%ReferenceObjectMap{joins: [_ | _] = joins}, var, predicate, resource) do
    children =
      Enum.map(joins, fn join ->
        Enum.find(Ash.Resource.Info.attributes(resource), &(Atom.to_string(&1.name) == to_string(join.child)))
      end)

    if Enum.all?(children, &(&1 != nil and &1.sensitive? != true)) do
      {:ok, %{type: :ref, var: var, predicate: predicate, children: Enum.map(children, & &1.name)}}
    else
      :error
    end
  end

  defp reference_info(_ref, _var, _predicate, _resource), do: :error

  defp others_ok?(others, infos) do
    ref_vars = for %{type: :ref, var: var} <- infos, do: var
    Enum.all?(others, &(&1 in ref_vars))
  end

  defp subject_attributes(resource, %Resource{subject_map: %SubjectMap{strategy: strategy, value: value}})
       when strategy in [:template, :column] do
    fields = if strategy == :template, do: Mapping.template_fields(value), else: [to_string(value)]

    attrs =
      for field <- fields,
          attr <- Ash.Resource.Info.attributes(resource),
          Atom.to_string(attr.name) == field,
          do: attr

    if Enum.any?(attrs, &(&1.sensitive? == true)),
      do: :error,
      else: {:ok, Enum.map(attrs, & &1.name)}
  end

  defp subject_attributes(_resource, _mapping), do: :error

  # -- plan assembly ---------------------------------------------------------------------

  defp assemble(sparql, resource, mapping, filters, infos, subject_attrs) do
    attr_infos = Enum.filter(infos, &(&1.type == :attr))
    by_var = Map.new(attr_infos, &{&1.var, &1})
    # Pushdown is gated on capability probing; only string collation (not expressible via can?/2)
    # uses the explicit bytewise allowlist in AshR2RML.Capability.
    caps = AshR2RML.Capability.probe(resource)
    ets? = AshR2RML.Capability.bytewise_string_order?(resource)
    pushed = if caps.filter, do: lower_filters(filters, by_var, ets?), else: []

    limit_mode =
      if caps.filter and caps.sort and caps.limit,
        do: limit_mode(Modifiers.parse(sparql), by_var, subject_attrs, mapping, resource, ets?),
        else: nil

    if pushed == [] and limit_mode == nil do
      :fallback
    else
      attrs = Enum.map(attr_infos, & &1.attribute)
      children = for %{type: :ref, children: children} <- infos, child <- children, do: child
      not_nil = for attribute <- Enum.uniq(attrs ++ subject_attrs), do: {:not_nil, attribute, nil}

      plan = %Plan{
        needed_attributes: Enum.uniq(attrs ++ children ++ subject_attrs),
        filter: {:and, not_nil ++ pushed},
        sort: if(limit_mode, do: Enum.map(limit_mode.keys, &{&1.attribute, &1.dir}), else: []),
        offset: 0,
        limit: if(limit_mode, do: limit_mode.fetch, else: nil)
      }

      {:ok,
       %Pushdown{
         resource: resource,
         mapping: mapping,
         plan: plan,
         keep: limit_mode && limit_mode.keep,
         fetch: limit_mode && limit_mode.fetch,
         keys: (limit_mode && limit_mode.keys) || []
       }}
    end
  end

  defp limit_mode(
         {:ok, %{order: [_ | _] = order, limit: limit, offset: offset}},
         by_var,
         subject_attrs,
         %Resource{subject_map: %SubjectMap{strategy: :template, value: template}},
         resource,
         ets?
       )
       when is_integer(limit) and limit > 0 do
    with true <- Ash.Resource.Info.authorizers(resource) == [],
         true <- length(subject_attrs) == length(Mapping.template_fields(template) |> Enum.uniq()),
         vars = Enum.map(order, &elem(&1, 0)),
         true <- vars == Enum.uniq(vars),
         {:ok, keys} <- sort_keys(order, by_var, ets?) do
      keep = offset + limit
      %{keys: keys, keep: keep, fetch: keep + 1}
    else
      _ -> nil
    end
  end

  defp limit_mode(_mods, _by_var, _subject_attrs, _mapping, _resource, _ets?), do: nil

  defp sort_keys(order, by_var, ets?) do
    order
    |> Enum.reduce_while({:ok, []}, fn {var, dir}, {:ok, acc} ->
      case Map.get(by_var, var) do
        %{kind: kind} = info when kind == :integer or (kind == :string and ets?) ->
          {:cont, {:ok, [Map.put(info, :dir, dir) | acc]}}

        _ ->
          {:halt, :error}
      end
    end)
    |> case do
      {:ok, keys} -> {:ok, Enum.reverse(keys)}
      :error -> :error
    end
  end

  # -- filters ---------------------------------------------------------------------------

  defp lower_filters(filters, by_var, ets?) do
    filters
    |> Enum.flat_map(&conjuncts/1)
    |> Enum.flat_map(&lower_filter(&1, by_var, ets?))
  end

  defp conjuncts(%FunctionCall.Builtin{name: :&&, arguments: [a, b]}), do: conjuncts(a) ++ conjuncts(b)
  defp conjuncts(other), do: [other]

  defp lower_filter(%FunctionCall.Builtin{name: name, arguments: [left, right]}, by_var, ets?)
       when is_map_key(@ops, name) do
    op = Map.fetch!(@ops, name)

    case {left, right} do
      {var, %RDF.Literal{} = lit} when is_binary(var) -> filter_term(op, var, lit, by_var, ets?)
      {%RDF.Literal{} = lit, var} when is_binary(var) -> filter_term(Map.fetch!(@flip, op), var, lit, by_var, ets?)
      _ -> []
    end
  end

  defp lower_filter(_other, _by_var, _ets?), do: []

  defp filter_term(op, var, literal, by_var, ets?) do
    with %{kind: kind, attribute: attribute} <- Map.get(by_var, var),
         {:ok, value} <- constant(kind, literal),
         true <- kind != :string or op in [:eq, :neq] or ets? do
      [{op, attribute, value}]
    else
      _ -> []
    end
  end

  defp constant(kind, %RDF.Literal{} = literal) do
    if RDF.Literal.valid?(literal) do
      datatype = literal |> RDF.Literal.datatype_id() |> RDF.IRI.to_string()
      value = RDF.Literal.value(literal)

      case {kind, datatype} do
        {:integer, @xsd_integer} -> {:ok, value}
        {:decimal, @xsd_integer} -> {:ok, Decimal.new(value)}
        {:decimal, @xsd_decimal} -> {:ok, value}
        {:string, @xsd_string} -> {:ok, value}
        _ -> :error
      end
    else
      :error
    end
  end

  # -- verification ----------------------------------------------------------------------

  @doc """
  Decides whether a limited pushdown's result can be trusted.

  `graph` is the graph materialized from the (possibly narrowed) read and `solution_count` the
  number of solutions SPARQL.ex produced over it. Returns `:ok` when the read provably saw every
  root row (`fewer than fetch` rows, or more, meaning the receiver did not narrow) or when it
  was truncated at `fetch` rows, produced at least `keep` solutions, and the sort key of row
  `keep` differs from that of the sentinel row `keep + 1`. Returns `:fallback` otherwise,
  including when a key literal is not typed as the mapping declares.
  """
  @spec verify(Pushdown.t(), RDF.Graph.t(), non_neg_integer()) :: :ok | :fallback
  def verify(%Pushdown{fetch: nil}, _graph, _solution_count), do: :ok

  def verify(%Pushdown{keys: keys, mapping: mapping, keep: keep, fetch: fetch}, graph, solution_count) do
    case root_key_rows(graph, mapping, keys) do
      {:ok, rows} -> decide(rows, keys, keep, fetch, solution_count)
      :error -> :fallback
    end
  rescue
    _ -> :fallback
  end

  defp decide(rows, keys, keep, fetch, solution_count) do
    n = length(rows)

    cond do
      # fewer rows than fetch: the read was exhaustive; more: the receiver did not narrow it
      n != fetch -> :ok
      solution_count < keep -> :fallback
      true -> tie_check(rows, keys, keep)
    end
  end

  defp tie_check(rows, keys, keep) do
    sorted = Enum.sort(rows, fn a, b -> compare_keys(a, b, keys) != :gt end)

    if compare_keys(Enum.at(sorted, keep - 1), Enum.at(sorted, keep), keys) == :eq,
      do: :fallback,
      else: :ok
  end

  defp compare_keys(a, b, keys) do
    [a, b, keys]
    |> Enum.zip()
    |> Enum.reduce_while(:eq, fn {x, y, %{dir: dir}}, :eq ->
      case Modifiers.compare(x, y) do
        :eq -> {:cont, :eq}
        :lt -> {:halt, if(dir == :desc, do: :gt, else: :lt)}
        :gt -> {:halt, if(dir == :desc, do: :lt, else: :gt)}
      end
    end)
  end

  defp root_key_rows(graph, mapping, keys) do
    graph
    |> RDF.Graph.subjects()
    |> Enum.reduce_while({:ok, []}, fn subject, {:ok, acc} ->
      if root_subject?(mapping, subject) do
        case key_values(graph, subject, keys) do
          {:ok, values} -> {:cont, {:ok, [values | acc]}}
          :error -> {:halt, :error}
        end
      else
        {:cont, {:ok, acc}}
      end
    end)
  end

  defp root_subject?(mapping, %RDF.IRI{} = subject) do
    match?({:ok, keys} when map_size(keys) > 0, AshR2RML.Subject.from_iri(mapping, RDF.IRI.to_string(subject)))
  end

  defp root_subject?(_mapping, _subject), do: false

  defp key_values(graph, subject, keys) do
    description = graph[subject]

    Enum.reduce_while(keys, {:ok, []}, fn %{predicate: predicate, datatype: datatype}, {:ok, acc} ->
      case RDF.Description.get(description, RDF.iri(predicate)) do
        [%RDF.Literal{} = literal] ->
          if literal |> RDF.Literal.datatype_id() |> RDF.IRI.to_string() == datatype do
            {:cont, {:ok, [RDF.Literal.value(literal) | acc]}}
          else
            {:halt, :error}
          end

        _ ->
          {:halt, :error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      :error -> :error
    end
  end
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
  alias AshR2RML.Capability
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
      caps = Capability.probe(resource)

      # A sorted/offset window is only meaningful when every part of it is pushed: a limit
      # without its sort (or offset) would drop rows, so the whole window is skipped instead.
      window? =
        (plan.sort == [] or caps.sort) and (plan.offset in [nil, 0] or caps.offset)

      resource
      |> Ash.Query.new()
      |> maybe_tenant(opts[:tenant])
      |> Ash.Query.for_read(action, %{}, read_opts(opts))
      |> Ash.Query.select(select)
      |> maybe_load(plan.needed_relationships)
      |> maybe_filter(if(caps.filter, do: filter_expr))
      |> maybe_sort(if(window?, do: plan.sort, else: []))
      |> maybe_offset(if(window?, do: plan.offset))
      |> maybe_limit(caps.limit and window?, effective_limit(plan.limit, max_rows))
    end
  end

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

  @doc "Post-read soundness check of a limited pushdown; see `AshR2RML.QueryBuilder.Lowering.verify/3`."
  @spec verify(AshR2RML.QueryBuilder.Pushdown.t(), RDF.Graph.t(), non_neg_integer()) :: :ok | :fallback
  def verify(pushdown, graph, solution_count),
    do: AshR2RML.QueryBuilder.Lowering.verify(pushdown, graph, solution_count)

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
