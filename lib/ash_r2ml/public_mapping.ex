# SPDX-FileCopyrightText: 2026 ash_r2ml contributors <https://github.com/seanchatmangpt/ash_r2ml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2ML.Refusal do
  @moduledoc "Typed fail-closed result for expected semantic mapping failures."

  @enforce_keys [:code, :subject, :detail]
  defstruct [:code, :subject, :detail, evidence: %{}]

  @type code ::
          :REFUSED_INVALID_CLASS_IRI
          | :REFUSED_MISSING_SUBJECT_MAP
          | :REFUSED_NON_UNIQUE_SEMANTIC_IDENTITY
          | :REFUSED_UNMAPPED_DATATYPE
          | :REFUSED_AMBIGUOUS_RELATIONSHIP
          | :REFUSED_INVALID_JOIN_CONDITION
          | :REFUSED_RELATIONSHIP_WITHOUT_PREDICATE
          | :REFUSED_R2RML_JOIN_WITHOUT_IDENTITY
          | :REFUSED_UNPROVEN_EQUIVALENCE
          | :REFUSED_UNKNOWN_ATTRIBUTE
          | :REFUSED_INVALID_LOGICAL_TABLE
          | :REFUSED_INVALID_GRAPH_MAP
          | :REFUSED_INVALID_TERM_MAP
          | :REFUSED_RELATIONSHIP_TARGET_UNMAPPED
          | :UNSUPPORTED_TERM_TYPE
          | :UNSUPPORTED_ASH_TYPE

  @type t :: %__MODULE__{
          code: code(),
          subject: term(),
          detail: String.t(),
          evidence: map()
        }

  @spec new(code(), term(), String.t(), map()) :: t()
  def new(code, subject, detail, evidence \\ %{}) do
    %__MODULE__{code: code, subject: subject, detail: detail, evidence: evidence}
  end
end

defmodule AshR2ML.Mapping.JoinCondition do
  @moduledoc "Explicit child/parent join used by an R2RML reference object map."
  @enforce_keys [:child, :parent]
  defstruct [:child, :parent]

  @type t :: %__MODULE__{child: String.t(), parent: String.t()}
end

defmodule AshR2ML.Mapping.Datatype do
  @moduledoc "Loss-aware correspondence between Ash, relational storage, and RDF datatypes."
  @enforce_keys [:rdf_datatype]
  defstruct [:ash_type, :rdf_datatype, :storage_type, :lexical_encoder]

  @type t :: %__MODULE__{
          ash_type: term(),
          rdf_datatype: String.t(),
          storage_type: term() | nil,
          lexical_encoder: term() | nil
        }
end

defmodule AshR2ML.Mapping.GraphMap do
  @moduledoc "Named-graph placement for a subject or predicate-object mapping."
  @enforce_keys [:strategy, :value]
  defstruct [:strategy, :value]

  @type strategy :: :constant | :template | :column
  @type t :: %__MODULE__{strategy: strategy(), value: String.t()}
end

defmodule AshR2ML.Mapping.SubjectMap do
  @moduledoc "Semantic RDF subject manufacture, independent of database identity."
  @enforce_keys [:strategy, :value]
  defstruct [:strategy, :value, term_type: :iri, graph_maps: []]

  @type strategy :: :template | :column | :constant | :blank_node
  @type term_type :: :iri | :blank_node
  @type t :: %__MODULE__{
          strategy: strategy(),
          value: String.t(),
          term_type: term_type(),
          graph_maps: [AshR2ML.Mapping.GraphMap.t()]
        }
end

defmodule AshR2ML.Mapping.ObjectMap do
  @moduledoc "Scalar RDF object manufacture for one predicate-object mapping."
  @enforce_keys [:strategy, :value]
  defstruct [
    :strategy,
    :value,
    :datatype,
    :language,
    term_type: :literal,
    graph_maps: []
  ]

  @type strategy :: :column | :template | :constant
  @type term_type :: :literal | :iri | :blank_node
  @type t :: %__MODULE__{
          strategy: strategy(),
          value: String.t(),
          datatype: AshR2ML.Mapping.Datatype.t() | nil,
          language: String.t() | nil,
          term_type: term_type(),
          graph_maps: [AshR2ML.Mapping.GraphMap.t()]
        }
end

defmodule AshR2ML.Mapping.PredicateObjectMap do
  @moduledoc "RDF datatype-property mapping normalized before R2RML serialization."
  @enforce_keys [:predicate_iri, :object_map]
  defstruct [:attribute, :predicate_iri, :object_map, graph_maps: []]

  @type t :: %__MODULE__{
          attribute: atom() | nil,
          predicate_iri: String.t(),
          object_map: AshR2ML.Mapping.ObjectMap.t(),
          graph_maps: [AshR2ML.Mapping.GraphMap.t()]
        }
end

defmodule AshR2ML.Mapping.ReferenceObjectMap do
  @moduledoc "RDF object-property mapping to a parent triples map through explicit joins."
  @enforce_keys [:predicate_iri, :parent_resource]
  defstruct [
    :relationship,
    :predicate_iri,
    :inverse_predicate,
    :parent_resource,
    joins: [],
    graph_maps: [],
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          relationship: atom() | nil,
          predicate_iri: String.t(),
          inverse_predicate: String.t() | nil,
          parent_resource: module() | String.t(),
          joins: [AshR2ML.Mapping.JoinCondition.t()],
          graph_maps: [AshR2ML.Mapping.GraphMap.t()],
          metadata: map()
        }
end

defmodule AshR2ML.Mapping.LogicalTable do
  @moduledoc "Exactly one relational logical source: table/view name or deterministic SQL query."
  defstruct [:table_name, :sql_query, :schema]

  @type t :: %__MODULE__{
          table_name: String.t() | nil,
          sql_query: String.t() | nil,
          schema: String.t() | nil
        }
end

defmodule AshR2ML.Mapping.Resource do
  @moduledoc "Canonical normalized mapping for one Ash resource / R2RML triples map."
  @enforce_keys [:ash_resource, :logical_table, :subject_map]
  defstruct [
    :ash_resource,
    :logical_table,
    :subject_map,
    class_iris: [],
    predicate_object_maps: [],
    reference_object_maps: [],
    graph_maps: [],
    identities: [],
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          ash_resource: module() | String.t(),
          logical_table: AshR2ML.Mapping.LogicalTable.t(),
          subject_map: AshR2ML.Mapping.SubjectMap.t(),
          class_iris: [String.t()],
          predicate_object_maps: [AshR2ML.Mapping.PredicateObjectMap.t()],
          reference_object_maps: [AshR2ML.Mapping.ReferenceObjectMap.t()],
          graph_maps: [AshR2ML.Mapping.GraphMap.t()],
          identities: [[atom()]],
          metadata: map()
        }
end

defmodule AshR2ML.Mapping.Bundle do
  @moduledoc "Dependency-closed set of normalized resource mappings."
  defstruct resources: []

  @type t :: %__MODULE__{resources: [AshR2ML.Mapping.Resource.t()]}
end

defmodule AshR2ML.Mapping do
  @moduledoc """
  Canonical public semantic mapping IR.

  All Ash-first and ontology-first entry paths normalize into these structures
  before R2RML serialization. Renderers are forbidden from rediscovering Ash
  relationships, storage columns, semantic identities, or datatype decisions.
  """

  alias AshR2ML.Mapping.{
    Bundle,
    GraphMap,
    JoinCondition,
    LogicalTable,
    ObjectMap,
    PredicateObjectMap,
    ReferenceObjectMap,
    Resource,
    SubjectMap
  }

  alias AshR2ML.Refusal

  @spec normalize(Resource.t()) :: Resource.t()
  def normalize(%Resource{} = resource) do
    %{
      resource
      | class_iris: Enum.sort(Enum.uniq(resource.class_iris)),
        graph_maps: sort_graph_maps(resource.graph_maps),
        identities: resource.identities |> Enum.map(&Enum.sort/1) |> Enum.uniq() |> Enum.sort(),
        predicate_object_maps:
          resource.predicate_object_maps
          |> Enum.map(&normalize_predicate_object_map/1)
          |> Enum.sort_by(&{&1.predicate_iri, to_string(&1.attribute || "")}),
        reference_object_maps:
          resource.reference_object_maps
          |> Enum.map(&normalize_reference_object_map/1)
          |> Enum.sort_by(&{&1.predicate_iri, to_string(&1.relationship || "")}),
        subject_map: normalize_subject_map(resource.subject_map)
    }
  end

  @spec normalize(Bundle.t()) :: Bundle.t()
  def normalize(%Bundle{} = bundle) do
    resources =
      bundle.resources
      |> Enum.map(&normalize/1)
      |> Enum.sort_by(&mapping_identity/1)

    %Bundle{resources: resources}
  end

  @spec validate(Resource.t() | Bundle.t()) :: :ok | {:error, [Refusal.t()]}
  def validate(%Resource{} = resource) do
    refusals =
      validate_logical_table(resource) ++
        validate_classes(resource) ++
        validate_subject(resource) ++
        validate_properties(resource) ++
        validate_references(resource) ++
        validate_graph_maps(resource)

    if refusals == [], do: :ok, else: {:error, refusals}
  end

  def validate(%Bundle{} = bundle) do
    bundle = normalize(bundle)
    resources = bundle.resources
    by_resource = Map.new(resources, &{&1.ash_resource, &1})

    refusals =
      Enum.flat_map(resources, fn resource ->
        own = case validate(resource) do
          :ok -> []
          {:error, values} -> values
        end

        target_refusals =
          Enum.flat_map(resource.reference_object_maps, fn reference ->
            case Map.get(by_resource, reference.parent_resource) do
              nil ->
                [
                  Refusal.new(
                    :REFUSED_RELATIONSHIP_TARGET_UNMAPPED,
                    {resource.ash_resource, reference.relationship},
                    "reference object map target is absent from the dependency-closed mapping bundle",
                    %{parent_resource: reference.parent_resource}
                  )
                ]

              parent ->
                validate_parent_identity(resource, reference, parent)
            end
          end)

        own ++ target_refusals
      end) ++ validate_duplicate_subject_contracts(resources)

    if refusals == [], do: :ok, else: {:error, refusals}
  end

  @spec mapping_identity(Resource.t()) :: String.t()
  def mapping_identity(%Resource{} = resource) do
    normalized = normalize(resource)

    digest =
      {
        normalized.class_iris,
        normalized.logical_table,
        normalized.subject_map
      }
      |> :erlang.term_to_binary([:deterministic])
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    "urn:ash-r2ml:triples-map:" <> digest
  end

  @spec template_fields(String.t()) :: [String.t()]
  def template_fields(template) when is_binary(template) do
    ~r/\{([^{}]+)\}/
    |> Regex.scan(template, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.sort()
  end

  def template_fields(_), do: []

  defp normalize_predicate_object_map(%PredicateObjectMap{} = mapping) do
    %{
      mapping
      | graph_maps: sort_graph_maps(mapping.graph_maps),
        object_map: normalize_object_map(mapping.object_map)
    }
  end

  defp normalize_reference_object_map(%ReferenceObjectMap{} = mapping) do
    %{
      mapping
      | graph_maps: sort_graph_maps(mapping.graph_maps),
        joins:
          mapping.joins
          |> Enum.uniq_by(&{&1.child, &1.parent})
          |> Enum.sort_by(&{&1.child, &1.parent})
    }
  end

  defp normalize_subject_map(%SubjectMap{} = map),
    do: %{map | graph_maps: sort_graph_maps(map.graph_maps)}

  defp normalize_object_map(%ObjectMap{} = map),
    do: %{map | graph_maps: sort_graph_maps(map.graph_maps)}

  defp sort_graph_maps(values) do
    values
    |> Enum.uniq_by(&{&1.strategy, &1.value})
    |> Enum.sort_by(&{&1.strategy, &1.value})
  end

  defp validate_logical_table(%Resource{logical_table: %LogicalTable{} = logical} = resource) do
    case {logical.table_name, logical.sql_query} do
      {table, nil} when is_binary(table) and table != "" -> []
      {nil, query} when is_binary(query) and query != "" -> []
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

  defp validate_logical_table(%Resource{} = resource) do
    [
      Refusal.new(
        :REFUSED_INVALID_LOGICAL_TABLE,
        resource.ash_resource,
        "mapping logical_table is missing"
      )
    ]
  end

  defp validate_classes(resource) do
    cond do
      resource.class_iris == [] ->
        [Refusal.new(:REFUSED_INVALID_CLASS_IRI, resource.ash_resource, "at least one RDF class IRI is required")]

      true ->
        resource.class_iris
        |> Enum.reject(&absolute_iri?/1)
        |> Enum.map(fn iri ->
          Refusal.new(:REFUSED_INVALID_CLASS_IRI, resource.ash_resource, "class IRI must be absolute", %{iri: iri})
        end)
    end
  end

  defp validate_subject(%Resource{subject_map: nil} = resource) do
    [Refusal.new(:REFUSED_MISSING_SUBJECT_MAP, resource.ash_resource, "RDF-emitting resource requires a subject map")]
  end

  defp validate_subject(%Resource{subject_map: %SubjectMap{} = subject} = resource) do
    allowed = [:template, :column, :constant, :blank_node]
    term_types = [:iri, :blank_node]

    []
    |> maybe_add(subject.strategy not in allowed, fn ->
      Refusal.new(:REFUSED_INVALID_TERM_MAP, resource.ash_resource, "unsupported subject strategy", %{strategy: subject.strategy})
    end)
    |> maybe_add(subject.term_type not in term_types, fn ->
      Refusal.new(:UNSUPPORTED_TERM_TYPE, resource.ash_resource, "unsupported subject term type", %{term_type: subject.term_type})
    end)
    |> maybe_add(not is_binary(subject.value) or subject.value == "", fn ->
      Refusal.new(:REFUSED_MISSING_SUBJECT_MAP, resource.ash_resource, "subject map value must be non-empty")
    end)
    |> maybe_add(subject.strategy == :constant and subject.term_type == :iri and not absolute_iri?(subject.value), fn ->
      Refusal.new(:REFUSED_MISSING_SUBJECT_MAP, resource.ash_resource, "constant IRI subject must be absolute", %{value: subject.value})
    end)
    |> Kernel.++(validate_template_fields(resource, subject))
    |> Kernel.++(validate_graph_maps_list(resource.ash_resource, subject.graph_maps))
  end

  defp validate_template_fields(resource, %SubjectMap{strategy: :template, value: template}) do
    mapped_columns =
      resource.predicate_object_maps
      |> Enum.flat_map(fn mapping ->
        case mapping.object_map do
          %ObjectMap{strategy: :column, value: value} -> [value]
          _ -> []
        end
      end)
      |> MapSet.new()

    missing = Enum.reject(template_fields(template), &MapSet.member?(mapped_columns, &1))

    if missing == [] do
      []
    else
      [
        Refusal.new(
          :REFUSED_MISSING_SUBJECT_MAP,
          resource.ash_resource,
          "subject template references columns not present in scalar property maps",
          %{missing: missing, template: template}
        )
      ]
    end
  end

  defp validate_template_fields(_resource, _subject), do: []

  defp validate_properties(resource) do
    Enum.flat_map(resource.predicate_object_maps, fn mapping ->
      object = mapping.object_map

      []
      |> maybe_add(not absolute_iri?(mapping.predicate_iri), fn ->
        Refusal.new(:REFUSED_RELATIONSHIP_WITHOUT_PREDICATE, {resource.ash_resource, mapping.attribute}, "predicate IRI must be absolute", %{predicate_iri: mapping.predicate_iri})
      end)
      |> maybe_add(object.term_type not in [:literal, :iri, :blank_node], fn ->
        Refusal.new(:UNSUPPORTED_TERM_TYPE, {resource.ash_resource, mapping.attribute}, "unsupported object term type", %{term_type: object.term_type})
      end)
      |> maybe_add(not is_binary(object.value) or object.value == "", fn ->
        Refusal.new(:REFUSED_INVALID_TERM_MAP, {resource.ash_resource, mapping.attribute}, "object map value must be non-empty")
      end)
      |> maybe_add(object.language && object.datatype, fn ->
        Refusal.new(:REFUSED_INVALID_TERM_MAP, {resource.ash_resource, mapping.attribute}, "language and datatype are mutually exclusive on one literal object map")
      end)
      |> Kernel.++(validate_datatype(resource, mapping))
      |> Kernel.++(validate_graph_maps_list({resource.ash_resource, mapping.attribute}, mapping.graph_maps ++ object.graph_maps))
    end)
  end

  defp validate_datatype(resource, mapping) do
    case mapping.object_map.datatype do
      nil -> []
      %{rdf_datatype: iri} when is_binary(iri) ->
        if absolute_iri?(iri) do
          []
        else
          [Refusal.new(:REFUSED_UNMAPPED_DATATYPE, {resource.ash_resource, mapping.attribute}, "RDF datatype IRI must be absolute", %{datatype: iri})]
        end

      value ->
        [Refusal.new(:REFUSED_UNMAPPED_DATATYPE, {resource.ash_resource, mapping.attribute}, "invalid datatype mapping", %{datatype: inspect(value)})]
    end
  end

  defp validate_references(resource) do
    Enum.flat_map(resource.reference_object_maps, fn reference ->
      []
      |> maybe_add(not absolute_iri?(reference.predicate_iri), fn ->
        Refusal.new(:REFUSED_RELATIONSHIP_WITHOUT_PREDICATE, {resource.ash_resource, reference.relationship}, "relationship predicate IRI must be absolute", %{predicate_iri: reference.predicate_iri})
      end)
      |> maybe_add(reference.inverse_predicate && not absolute_iri?(reference.inverse_predicate), fn ->
        Refusal.new(:REFUSED_UNPROVEN_EQUIVALENCE, {resource.ash_resource, reference.relationship}, "inverse predicate must be an absolute IRI when supplied", %{inverse_predicate: reference.inverse_predicate})
      end)
      |> maybe_add(reference.joins == [], fn ->
        Refusal.new(:REFUSED_INVALID_JOIN_CONDITION, {resource.ash_resource, reference.relationship}, "reference object map requires at least one join condition")
      end)
      |> Kernel.++(Enum.flat_map(reference.joins, &validate_join(resource, reference, &1)))
      |> Kernel.++(validate_graph_maps_list({resource.ash_resource, reference.relationship}, reference.graph_maps))
    end)
  end

  defp validate_join(resource, reference, %JoinCondition{child: child, parent: parent}) do
    if non_empty_string?(child) and non_empty_string?(parent) do
      []
    else
      [
        Refusal.new(
          :REFUSED_INVALID_JOIN_CONDITION,
          {resource.ash_resource, reference.relationship},
          "join child and parent columns must both be non-empty",
          %{child: child, parent: parent}
        )
      ]
    end
  end

  defp validate_join(resource, reference, other) do
    [
      Refusal.new(
        :REFUSED_INVALID_JOIN_CONDITION,
        {resource.ash_resource, reference.relationship},
        "join must be a JoinCondition",
        %{join: inspect(other)}
      )
    ]
  end

  defp validate_graph_maps(resource),
    do: validate_graph_maps_list(resource.ash_resource, resource.graph_maps)

  defp validate_graph_maps_list(subject, graph_maps) do
    Enum.flat_map(graph_maps, fn
      %GraphMap{strategy: :constant, value: value} ->
        if absolute_iri?(value) do
          []
        else
          [Refusal.new(:REFUSED_INVALID_GRAPH_MAP, subject, "constant graph IRI must be absolute", %{value: value})]
        end

      %GraphMap{strategy: strategy, value: value} when strategy in [:template, :column] ->
        if non_empty_string?(value) do
          []
        else
          [Refusal.new(:REFUSED_INVALID_GRAPH_MAP, subject, "graph map value must be non-empty", %{strategy: strategy})]
        end

      other ->
        [Refusal.new(:REFUSED_INVALID_GRAPH_MAP, subject, "unsupported graph map", %{graph_map: inspect(other)})]
    end)
  end

  defp validate_parent_identity(resource, reference, parent) do
    parent_columns = MapSet.new(parent.identities |> List.flatten() |> Enum.map(&to_string/1))
    joined_parent_columns = MapSet.new(Enum.map(reference.joins, & &1.parent))

    cond do
      parent.identities == [] ->
        [
          Refusal.new(
            :REFUSED_R2RML_JOIN_WITHOUT_IDENTITY,
            {resource.ash_resource, reference.relationship},
            "parent mapping has no admitted stable identity",
            %{parent_resource: parent.ash_resource}
          )
        ]

      MapSet.disjoint?(parent_columns, joined_parent_columns) ->
        [
          Refusal.new(
            :REFUSED_R2RML_JOIN_WITHOUT_IDENTITY,
            {resource.ash_resource, reference.relationship},
            "join does not target any admitted parent identity column",
            %{parent_resource: parent.ash_resource, joins: reference.joins, identities: parent.identities}
          )
        ]

      true -> []
    end
  end

  defp validate_duplicate_subject_contracts(resources) do
    resources
    |> Enum.group_by(fn resource -> {resource.logical_table, resource.subject_map} end)
    |> Enum.flat_map(fn
      {_key, [_one]} -> []
      {key, many} ->
        class_sets = many |> Enum.map(&MapSet.new(&1.class_iris))
        overlap? = pairwise_overlap?(class_sets)

        if overlap? do
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
    end)
  end

  defp pairwise_overlap?([]), do: false
  defp pairwise_overlap?([head | tail]) do
    Enum.any?(tail, &(not MapSet.disjoint?(head, &1))) or pairwise_overlap?(tail)
  end

  defp absolute_iri?(value) when is_binary(value) do
    case URI.parse(value) do
      %URI{scheme: scheme} when is_binary(scheme) and scheme != "" -> true
      _ -> false
    end
  end

  defp absolute_iri?(_), do: false
  defp non_empty_string?(value), do: is_binary(value) and value != ""

  defp maybe_add(acc, true, fun), do: acc ++ [fun.()]
  defp maybe_add(acc, false, _fun), do: acc
end
