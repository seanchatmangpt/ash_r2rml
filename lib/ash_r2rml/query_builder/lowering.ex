# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

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
  alias AshR2RML.QueryBuilder.{Modifiers, Plan, Pushdown, Verification}
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
  end

  @doc "Post-read soundness check of a limited pushdown; see `AshR2RML.QueryBuilder.Verification`."
  @spec verify(Pushdown.t(), RDF.Graph.t(), non_neg_integer()) :: :ok | :fallback
  defdelegate verify(pushdown, graph, solution_count), to: Verification

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
    root_triples
    |> Enum.reduce_while({:ok, []}, fn triple, {:ok, acc} ->
      case classify_triple(triple, resource, mapping) do
        {:ok, info} -> {:cont, {:ok, [info | acc]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, infos} -> {:ok, Enum.reverse(infos)}
      :error -> :error
    end
  end

  defp classify_triple({_s, _p, var} = triple, resource, mapping) do
    predicate = pred(triple)
    poms = Enum.filter(mapping.predicate_object_maps || [], &(&1.predicate_iri == predicate))
    refs = Enum.filter(mapping.reference_object_maps || [], &(&1.predicate_iri == predicate))

    case {poms, refs} do
      {[pom], []} -> attribute_info(pom, var, predicate, resource)
      {[], [ref]} -> reference_info(ref, var, predicate, resource)
      _ -> :error
    end
  end

  defp attribute_info(pom, var, predicate, resource) do
    attribute = pom.attribute

    with true <- is_atom(attribute) and not is_nil(attribute),
         %ObjectMap{strategy: :column, term_type: :literal, language: nil} = om <- pom.object_map,
         true <- om.graph_maps in [nil, []] and pom.graph_maps in [nil, []],
         true <- to_string(om.value) == Atom.to_string(attribute),
         {:ok, declared} <- declared_datatype(om.datatype),
         %{sensitive?: false} = ash_attr <- Ash.Resource.Info.attribute(resource, attribute),
         # A field-policy-gated attribute must never be filtered/sorted in the data layer: the
         # row count would act as an oracle on the hidden value.
         false <- AshR2RML.Security.field_policy_protected?(resource, attribute) do
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
    ash_kind = ash_kind(ash_type)
    if declared in [nil, default_datatype(ash_kind)], do: ash_kind, else: :other
  end

  defp ash_kind(Ash.Type.Integer), do: :integer
  defp ash_kind(Ash.Type.String), do: :string
  defp ash_kind(Ash.Type.Decimal), do: :decimal
  defp ash_kind(_), do: :other

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
    ctx = %{ets?: ets?, decimal?: AshR2RML.Capability.decimal_pushdown?(resource)}
    pushed = if caps.filter, do: lower_filters(filters, by_var, ctx), else: []

    limit_mode =
      if caps.filter and caps.sort and caps.limit,
        do: limit_mode(Modifiers.parse(sparql), by_var, subject_attrs, mapping, resource, ets?),
        else: nil

    if pushed == [] and limit_mode == nil do
      :fallback
    else
      {:ok, pushdown(resource, mapping, infos, subject_attrs, pushed, limit_mode)}
    end
  end

  defp pushdown(resource, mapping, infos, subject_attrs, pushed, limit_mode) do
    attrs = for %{type: :attr, attribute: attribute} <- infos, do: attribute
    children = for %{type: :ref, children: children} <- infos, child <- children, do: child
    not_nil = for attribute <- Enum.uniq(attrs ++ subject_attrs), do: {:not_nil, attribute, nil}

    plan = %Plan{
      needed_attributes: Enum.uniq(attrs ++ children ++ subject_attrs),
      filter: {:and, not_nil ++ pushed},
      sort: if(limit_mode, do: Enum.map(limit_mode.keys, &{&1.attribute, &1.dir}), else: []),
      offset: 0,
      limit: if(limit_mode, do: limit_mode.fetch, else: nil)
    }

    %Pushdown{
      resource: resource,
      mapping: mapping,
      plan: plan,
      keep: limit_mode && limit_mode.keep,
      fetch: limit_mode && limit_mode.fetch,
      keys: (limit_mode && limit_mode.keys) || []
    }
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

  defp lower_filters(filters, by_var, ctx) do
    filters
    |> Enum.flat_map(&conjuncts/1)
    |> Enum.flat_map(&lower_filter(&1, by_var, ctx))
  end

  defp conjuncts(%FunctionCall.Builtin{name: :&&, arguments: [a, b]}), do: conjuncts(a) ++ conjuncts(b)
  defp conjuncts(other), do: [other]

  defp lower_filter(%FunctionCall.Builtin{name: name, arguments: [left, right]}, by_var, ctx)
       when is_map_key(@ops, name) do
    op = Map.fetch!(@ops, name)

    case {left, right} do
      {var, %RDF.Literal{} = lit} when is_binary(var) -> filter_term(op, var, lit, by_var, ctx)
      {%RDF.Literal{} = lit, var} when is_binary(var) -> filter_term(Map.fetch!(@flip, op), var, lit, by_var, ctx)
      _ -> []
    end
  end

  defp lower_filter(_other, _by_var, _ctx), do: []

  defp filter_term(op, var, literal, by_var, ctx) do
    with %{kind: kind, attribute: attribute} <- Map.get(by_var, var),
         {:ok, value} <- constant(kind, literal),
         true <- kind != :string or op in [:eq, :neq] or ctx.ets?,
         true <- kind != :decimal or ctx.decimal? do
      [{op, attribute, value}]
    else
      _ -> []
    end
  end

  defp constant(kind, %RDF.Literal{} = literal) do
    if RDF.Literal.valid?(literal) do
      datatype = literal |> RDF.Literal.datatype_id() |> RDF.IRI.to_string()
      typed_constant(kind, datatype, RDF.Literal.value(literal))
    else
      :error
    end
  end

  defp typed_constant(:integer, @xsd_integer, value), do: {:ok, value}
  defp typed_constant(:decimal, @xsd_integer, value), do: {:ok, Decimal.new(value)}
  defp typed_constant(:decimal, @xsd_decimal, value), do: {:ok, value}
  defp typed_constant(:string, @xsd_string, value), do: {:ok, value}
  defp typed_constant(_kind, _datatype, _value), do: :error
end
