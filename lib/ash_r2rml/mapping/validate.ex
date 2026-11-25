# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Mapping.Validate do
  @moduledoc """
  Fail-closed validation of the mapping IR, one named step per rule.

  Called through `AshR2RML.Mapping.validate/1`; refusal codes and ordering are
  part of the public contract.

      iex> AshR2RML.Mapping.Validate.absolute_iri?("http://schema.org/a")
      true
      iex> AshR2RML.Mapping.Validate.absolute_iri?("relative/path")
      false
  """

  alias AshR2RML.Mapping

  alias AshR2RML.Mapping.{
    Bundle,
    GraphMap,
    JoinCondition,
    LogicalTable,
    ObjectMap,
    ReferenceObjectMap,
    Resource,
    SubjectMap
  }

  alias AshR2RML.Refusal

  @bridge_keys [
    :source_parent_column,
    :source_join_column,
    :destination_join_column,
    :destination_parent_column
  ]

  @spec run(Resource.t() | Bundle.t()) :: :ok | {:error, [Refusal.t()]}
  def run(%Resource{} = resource) do
    refusals =
      logical_table(resource) ++
        classes(resource) ++
        subject(resource) ++
        properties(resource) ++
        duplicate_properties(resource) ++
        references(resource) ++
        duplicate_references(resource) ++
        graph_maps(resource)

    to_result(refusals)
  end

  def run(%Bundle{} = bundle) do
    bundle = Mapping.normalize(bundle)
    by_resource = Map.new(bundle.resources, &{&1.ash_resource, &1})

    refusals =
      Enum.flat_map(bundle.resources, &bundled_resource(&1, by_resource)) ++
        duplicate_subject_contracts(bundle.resources)

    to_result(refusals)
  end

  defp to_result([]), do: :ok
  defp to_result(refusals), do: {:error, refusals}

  # -- bundle rules ----------------------------------------------------------

  defp bundled_resource(resource, by_resource) do
    own =
      case run(resource) do
        :ok -> []
        {:error, values} -> values
      end

    targets =
      Enum.flat_map(resource.reference_object_maps, &reference_target(resource, &1, by_resource))

    own ++ targets
  end

  defp reference_target(resource, reference, by_resource) do
    case Map.fetch(by_resource, reference.parent_resource) do
      {:ok, parent} -> parent_subject_identity(resource, reference, parent)
      :error -> [unmapped_target(resource, reference)]
    end
  end

  defp unmapped_target(resource, reference) do
    Refusal.new(
      :REFUSED_RELATIONSHIP_TARGET_UNMAPPED,
      {resource.ash_resource, reference.relationship},
      "reference object map target is absent from the dependency-closed mapping bundle",
      %{parent_resource: reference.parent_resource}
    )
  end

  defp parent_subject_identity(resource, reference, parent) do
    if Mapping.stable_subject_identity?(parent) do
      []
    else
      [
        Refusal.new(
          :REFUSED_R2RML_JOIN_WITHOUT_IDENTITY,
          {resource.ash_resource, reference.relationship},
          "parent triples map has no stable semantic subject identity",
          %{
            parent_resource: parent.ash_resource,
            subject_map: parent.subject_map,
            identities: parent.identities
          }
        )
      ]
    end
  end

  defp duplicate_subject_contracts(resources) do
    resources
    |> Enum.group_by(fn resource -> {resource.logical_table, resource.subject_map} end)
    |> Enum.flat_map(fn
      {_key, [_one]} -> []
      {key, many} -> duplicate_contract_refusals(key, many)
    end)
  end

  defp duplicate_contract_refusals(key, many) do
    if many |> Enum.map(&MapSet.new(&1.class_iris)) |> pairwise_overlap?() do
      [
        Refusal.new(
          :REFUSED_NON_UNIQUE_SEMANTIC_IDENTITY,
          Enum.map(many, & &1.ash_resource),
          "multiple mappings with overlapping RDF classes manufacture the same subject contract",
          %{subject_contract: key}
        )
      ]
    else
      []
    end
  end

  defp pairwise_overlap?([]), do: false

  defp pairwise_overlap?([head | tail]),
    do: Enum.any?(tail, &(not MapSet.disjoint?(head, &1))) or pairwise_overlap?(tail)

  # -- logical table ---------------------------------------------------------

  defp logical_table(%Resource{logical_table: %LogicalTable{} = logical} = resource) do
    case {logical.table_name, logical.sql_query} do
      {table, nil} when is_binary(table) and table != "" ->
        []

      {nil, query} when is_binary(query) and query != "" ->
        []

      _ ->
        [
          Refusal.new(
            :REFUSED_INVALID_LOGICAL_TABLE,
            resource.ash_resource,
            "mapping requires exactly one non-empty table_name or sql_query",
            %{logical_table: logical}
          )
        ]
    end
  end

  defp logical_table(%Resource{} = resource) do
    [
      Refusal.new(
        :REFUSED_INVALID_LOGICAL_TABLE,
        resource.ash_resource,
        "mapping logical_table is missing"
      )
    ]
  end

  # -- classes ---------------------------------------------------------------

  defp classes(%Resource{class_iris: [], ash_resource: subject}) do
    [Refusal.new(:REFUSED_INVALID_CLASS_IRI, subject, "at least one RDF class IRI is required")]
  end

  defp classes(%Resource{class_iris: iris, ash_resource: subject}) do
    iris
    |> Enum.reject(&absolute_iri?/1)
    |> Enum.map(&Refusal.new(:REFUSED_INVALID_CLASS_IRI, subject, "class IRI must be absolute", %{iri: &1}))
  end

  # -- subject ---------------------------------------------------------------

  defp subject(%Resource{subject_map: nil} = resource) do
    [
      Refusal.new(
        :REFUSED_MISSING_SUBJECT_MAP,
        resource.ash_resource,
        "RDF-emitting resource requires a subject map"
      )
    ]
  end

  defp subject(%Resource{subject_map: %SubjectMap{} = subject} = resource) do
    []
    |> maybe_add(subject_strategy(resource, subject))
    |> maybe_add(subject_term_type(resource, subject))
    |> maybe_add(subject_value(resource, subject))
    |> maybe_add(subject_constant_iri(resource, subject))
    |> Kernel.++(subject_columns(resource, subject))
    |> Kernel.++(graph_maps_list(resource.ash_resource, subject.graph_maps))
    |> maybe_add(subject_identity(resource, subject))
  end

  defp subject_strategy(resource, subject) do
    if subject.strategy not in [:template, :column, :constant, :blank_node] do
      Refusal.new(:REFUSED_INVALID_TERM_MAP, resource.ash_resource, "unsupported subject strategy", %{
        strategy: subject.strategy
      })
    end
  end

  defp subject_term_type(resource, subject) do
    if subject.term_type not in [:iri, :blank_node] do
      Refusal.new(:UNSUPPORTED_TERM_TYPE, resource.ash_resource, "unsupported subject term type", %{
        term_type: subject.term_type
      })
    end
  end

  defp subject_value(resource, subject) do
    if not non_empty_string?(subject.value) do
      Refusal.new(
        :REFUSED_MISSING_SUBJECT_MAP,
        resource.ash_resource,
        "subject map value must be non-empty"
      )
    end
  end

  defp subject_constant_iri(resource, subject) do
    if subject.strategy == :constant and subject.term_type == :iri and
         not absolute_iri?(subject.value) do
      Refusal.new(
        :REFUSED_MISSING_SUBJECT_MAP,
        resource.ash_resource,
        "constant IRI subject must be absolute",
        %{value: subject.value}
      )
    end
  end

  defp subject_identity(resource, subject) do
    if not Mapping.stable_subject_identity?(resource) do
      Refusal.new(
        :REFUSED_NON_UNIQUE_SEMANTIC_IDENTITY,
        resource.ash_resource,
        "subject mapping is not proven by an admitted Ash/semantic identity",
        %{subject_map: subject, identities: resource.identities}
      )
    end
  end

  defp subject_columns(resource, %SubjectMap{strategy: :template, value: template}) do
    template_refusals(
      resource,
      template,
      :REFUSED_MISSING_SUBJECT_MAP,
      resource.ash_resource,
      "subject template references columns absent from the admitted resource mapping"
    )
  end

  defp subject_columns(resource, %SubjectMap{strategy: :column, value: column}) do
    if MapSet.member?(available_columns(resource), column) do
      []
    else
      [
        Refusal.new(
          :REFUSED_MISSING_SUBJECT_MAP,
          resource.ash_resource,
          "subject column is absent from the admitted resource mapping",
          %{column: column}
        )
      ]
    end
  end

  defp subject_columns(resource, %SubjectMap{strategy: :blank_node, value: template})
       when is_binary(template) do
    template_refusals(
      resource,
      template,
      :REFUSED_MISSING_SUBJECT_MAP,
      resource.ash_resource,
      "blank-node subject template references columns absent from the admitted resource mapping"
    )
  end

  defp subject_columns(_resource, _subject), do: []

  # One refusal naming every template field the resource mapping cannot supply.
  defp template_refusals(resource, template, code, subject, detail) do
    available = available_columns(resource)

    case Enum.reject(Mapping.template_fields(template), &MapSet.member?(available, &1)) do
      [] -> []
      missing -> [Refusal.new(code, subject, detail, %{missing: missing, template: template})]
    end
  end

  # -- predicate-object maps -------------------------------------------------

  defp properties(resource) do
    Enum.flat_map(resource.predicate_object_maps, &property(resource, &1))
  end

  defp property(resource, mapping) do
    object = mapping.object_map
    subject = {resource.ash_resource, mapping.attribute}

    []
    |> maybe_add(property_predicate(subject, mapping))
    |> maybe_add(property_term_type(subject, object))
    |> maybe_add(property_value(subject, object))
    |> maybe_add(property_language_datatype(subject, object))
    |> maybe_add(property_constant_iri(subject, object))
    |> Kernel.++(object_template(resource, mapping, object))
    |> Kernel.++(datatype(subject, object.datatype))
    |> Kernel.++(graph_maps_list(subject, mapping.graph_maps ++ object.graph_maps))
  end

  defp property_predicate(subject, mapping) do
    if not absolute_iri?(mapping.predicate_iri) do
      Refusal.new(
        :REFUSED_RELATIONSHIP_WITHOUT_PREDICATE,
        subject,
        "predicate IRI must be absolute",
        %{predicate_iri: mapping.predicate_iri}
      )
    end
  end

  defp property_term_type(subject, object) do
    if object.term_type not in [:literal, :iri, :blank_node] do
      Refusal.new(:UNSUPPORTED_TERM_TYPE, subject, "unsupported object term type", %{
        term_type: object.term_type
      })
    end
  end

  defp property_value(subject, object) do
    if not non_empty_string?(object.value) do
      Refusal.new(:REFUSED_INVALID_TERM_MAP, subject, "object map value must be non-empty")
    end
  end

  defp property_language_datatype(subject, object) do
    if not is_nil(object.language) and not is_nil(object.datatype) do
      Refusal.new(
        :REFUSED_INVALID_TERM_MAP,
        subject,
        "language and datatype are mutually exclusive on one literal object map"
      )
    end
  end

  defp property_constant_iri(subject, object) do
    if object.strategy == :constant and object.term_type == :iri and
         not absolute_iri?(object.value) do
      Refusal.new(
        :REFUSED_INVALID_TERM_MAP,
        subject,
        "constant IRI object map must be an absolute IRI",
        %{value: object.value}
      )
    end
  end

  defp object_template(resource, mapping, %ObjectMap{strategy: :template, value: value})
       when is_binary(value) do
    template_refusals(
      resource,
      value,
      :REFUSED_INVALID_TERM_MAP,
      {resource.ash_resource, mapping.attribute},
      "object template references columns absent from the admitted resource mapping"
    )
  end

  defp object_template(_resource, _mapping, _object), do: []

  defp datatype(_subject, nil), do: []

  defp datatype(subject, %{rdf_datatype: iri}) when is_binary(iri) do
    if absolute_iri?(iri) do
      []
    else
      [
        Refusal.new(:REFUSED_UNMAPPED_DATATYPE, subject, "RDF datatype IRI must be absolute", %{
          datatype: iri
        })
      ]
    end
  end

  defp datatype(subject, value) do
    [
      Refusal.new(:REFUSED_UNMAPPED_DATATYPE, subject, "invalid datatype mapping", %{
        datatype: inspect(value)
      })
    ]
  end

  defp duplicate_properties(resource) do
    resource.predicate_object_maps
    |> duplicate_keys(&{&1.attribute, &1.predicate_iri})
    |> Enum.map(fn {attribute, predicate} = key ->
      Refusal.new(
        :REFUSED_INVALID_TERM_MAP,
        {resource.ash_resource, attribute},
        "duplicate (attribute, predicate) predicate-object map",
        %{key: key, predicate_iri: predicate}
      )
    end)
  end

  # -- reference object maps -------------------------------------------------

  defp references(resource) do
    Enum.flat_map(resource.reference_object_maps, &reference(resource, &1))
  end

  defp reference(resource, reference) do
    subject = {resource.ash_resource, reference.relationship}

    base =
      []
      |> maybe_add(reference_predicate(subject, reference))
      |> maybe_add(reference_inverse(subject, reference))

    base ++
      reference_joins(resource, reference) ++
      graph_maps_list(subject, reference.graph_maps)
  end

  defp reference_predicate(subject, reference) do
    if not absolute_iri?(reference.predicate_iri) do
      Refusal.new(
        :REFUSED_RELATIONSHIP_WITHOUT_PREDICATE,
        subject,
        "relationship predicate IRI must be absolute",
        %{predicate_iri: reference.predicate_iri}
      )
    end
  end

  defp reference_inverse(subject, reference) do
    if reference.inverse_predicate && not absolute_iri?(reference.inverse_predicate) do
      Refusal.new(
        :REFUSED_UNPROVEN_EQUIVALENCE,
        subject,
        "inverse predicate must be an absolute IRI when supplied",
        %{inverse_predicate: reference.inverse_predicate}
      )
    end
  end

  defp reference_joins(resource, %ReferenceObjectMap{metadata: %{kind: :many_to_many}} = reference),
    do: many_to_many_bridge(resource, reference)

  defp reference_joins(resource, reference) do
    subject = {resource.ash_resource, reference.relationship}

    []
    |> maybe_add(reference_requires_join(subject, reference))
    |> Kernel.++(Enum.flat_map(reference.joins, &join(subject, &1)))
  end

  defp reference_requires_join(subject, reference) do
    if reference.joins == [] do
      Refusal.new(
        :REFUSED_INVALID_JOIN_CONDITION,
        subject,
        "reference object map requires at least one join condition"
      )
    end
  end

  defp many_to_many_bridge(resource, reference) do
    metadata = reference.metadata
    subject = {resource.ash_resource, reference.relationship}
    bridge_columns = bridge_columns(metadata)

    []
    |> maybe_add(bridge_through_table(subject, Map.get(metadata, :through_logical_table)))
    |> maybe_add(bridge_complete(subject, metadata, bridge_columns))
  end

  defp bridge_columns(metadata) do
    cond do
      Enum.all?(@bridge_keys, &Map.has_key?(metadata, &1)) ->
        Enum.map(@bridge_keys, &Map.fetch!(metadata, &1))

      match?(%JoinCondition{}, Map.get(metadata, :source_to_join)) and
          match?(%JoinCondition{}, Map.get(metadata, :join_to_destination)) ->
        a = metadata.source_to_join
        b = metadata.join_to_destination
        [a.child, a.parent, b.child, b.parent]

      true ->
        []
    end
  end

  defp bridge_through_table(subject, through) do
    if not match?(%LogicalTable{}, through) do
      Refusal.new(
        :REFUSED_INVALID_LOGICAL_TABLE,
        subject,
        "many_to_many reference requires a normalized through logical table"
      )
    end
  end

  defp bridge_complete(subject, metadata, columns) do
    if columns == [] or Enum.any?(columns, &(not non_empty_string?(&1))) do
      Refusal.new(
        :REFUSED_INVALID_JOIN_CONDITION,
        subject,
        "many_to_many reference requires complete source/bridge/destination join columns",
        %{metadata: metadata}
      )
    end
  end

  defp join(subject, %JoinCondition{child: child, parent: parent}) do
    if non_empty_string?(child) and non_empty_string?(parent) do
      []
    else
      [
        Refusal.new(
          :REFUSED_INVALID_JOIN_CONDITION,
          subject,
          "join child and parent columns must both be non-empty",
          %{child: child, parent: parent}
        )
      ]
    end
  end

  defp join(subject, other) do
    [
      Refusal.new(:REFUSED_INVALID_JOIN_CONDITION, subject, "join must be a JoinCondition", %{
        join: inspect(other)
      })
    ]
  end

  defp duplicate_references(resource) do
    resource.reference_object_maps
    |> duplicate_keys(&{&1.relationship, &1.predicate_iri})
    |> Enum.map(fn {relationship, predicate} = key ->
      Refusal.new(
        :REFUSED_AMBIGUOUS_RELATIONSHIP,
        {resource.ash_resource, relationship},
        "duplicate (relationship, predicate) reference object map",
        %{key: key, predicate_iri: predicate}
      )
    end)
  end

  # -- graph maps ------------------------------------------------------------

  defp graph_maps(resource), do: graph_maps_list(resource.ash_resource, resource.graph_maps)

  defp graph_maps_list(subject, graph_maps) do
    Enum.flat_map(graph_maps, &graph_map(subject, &1))
  end

  defp graph_map(subject, %GraphMap{strategy: :constant, value: value}) do
    if absolute_iri?(value) do
      []
    else
      [
        Refusal.new(:REFUSED_INVALID_GRAPH_MAP, subject, "constant graph IRI must be absolute", %{
          value: value
        })
      ]
    end
  end

  defp graph_map(subject, %GraphMap{strategy: strategy, value: value})
       when strategy in [:template, :column] do
    if non_empty_string?(value) do
      []
    else
      [
        Refusal.new(:REFUSED_INVALID_GRAPH_MAP, subject, "graph map value must be non-empty", %{
          strategy: strategy
        })
      ]
    end
  end

  defp graph_map(subject, other) do
    [
      Refusal.new(:REFUSED_INVALID_GRAPH_MAP, subject, "unsupported graph map", %{
        graph_map: inspect(other)
      })
    ]
  end

  # -- shared helpers --------------------------------------------------------

  defp duplicate_keys(items, key_fun) do
    items
    |> Enum.map(key_fun)
    |> Enum.frequencies()
    |> Enum.filter(fn {_key, count} -> count > 1 end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.sort()
  end

  defp available_columns(resource) do
    metadata_columns = Map.get(resource.metadata, :attribute_columns, %{}) |> Map.values()
    identity_cols = resource.identities |> List.flatten() |> Enum.map(&to_string/1)

    property_columns =
      Enum.flat_map(resource.predicate_object_maps, fn mapping ->
        case mapping.object_map do
          %ObjectMap{strategy: :column, value: value} -> [value]
          _ -> []
        end
      end)

    MapSet.new(metadata_columns ++ identity_cols ++ property_columns)
  end

  # IRIREF forbids: control chars, space, < > " { } | ^ ` \
  defp iri_forbidden?(value), do: Regex.match?(~r/[\x00-\x20\x7f<>"{}|^`\\]/, value)

  @doc false
  @spec absolute_iri?(term()) :: boolean()
  def absolute_iri?(value) when is_binary(value) do
    not iri_forbidden?(value) and
      match?(%URI{scheme: scheme} when is_binary(scheme) and scheme != "", URI.parse(value))
  end

  def absolute_iri?(_), do: false

  defp non_empty_string?(value), do: is_binary(value) and value != ""

  # Appends a refusal when the rule step produced one (nil means the rule passed).
  defp maybe_add(acc, nil), do: acc
  defp maybe_add(acc, %Refusal{} = refusal), do: acc ++ [refusal]
end
