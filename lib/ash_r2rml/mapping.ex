# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Refusal do
  @moduledoc """
  Typed fail-closed result for expected semantic mapping failures.

      iex> AshR2RML.Refusal.new(:REFUSED_INVALID_CLASS_IRI, MyApp.Person, "class IRI must be absolute").code
      :REFUSED_INVALID_CLASS_IRI

  A refusal is also a `Splode.Error`: it can be raised, `Exception.message/1` renders
  `CODE: detail`, and `Ash.Error.to_error_class/1` classifies it by its code (see `class_for/1`).
  """

  @enforce_keys [:code, :subject, :detail]
  use Splode.Error, fields: [:code, :subject, :detail, evidence: %{}], class: :invalid

  @forbidden_codes [
    :REFUSED_UNAUTHORIZED,
    :REFUSED_SENSITIVE_ATTRIBUTE_MATERIALIZATION,
    :REFUSED_ENCRYPTED_ATTRIBUTE_PROJECTION
  ]

  @unknown_codes [
    :REFUSED_QUERY_TIMEOUT,
    :REFUSED_READ_FAILED,
    :REFUSED_WORKER_CRASHED,
    :REFUSED_RESULT_LIMIT_EXCEEDED,
    :REFUSED_TRIPLE_LIMIT_EXCEEDED,
    :REFUSED_MEMORY_LIMIT_EXCEEDED,
    :REFUSED_RESOURCE_BOUND,
    :REFUSED_MANIFEST_GENERATION
  ]

  @doc """
  The Ash error class of a refusal code: policy and sensitivity refusals are `:forbidden`,
  runtime and bound failures are `:unknown`, mapping/option/validation refusals are `:invalid`.

      iex> AshR2RML.Refusal.class_for(:REFUSED_UNAUTHORIZED)
      :forbidden
      iex> AshR2RML.Refusal.class_for(:REFUSED_INVALID_OPTION)
      :invalid
  """
  @spec class_for(atom()) :: :forbidden | :invalid | :unknown
  def class_for(code) when code in @forbidden_codes, do: :forbidden
  def class_for(code) when code in @unknown_codes, do: :unknown
  def class_for(_code), do: :invalid

  @doc false
  @impl Exception
  def exception(opts) do
    refusal = super(opts)
    %{refusal | class: class_for(refusal.code)}
  end

  @impl Exception
  def message(%__MODULE__{code: code, detail: detail} = refusal) do
    detail_text = if is_binary(detail), do: detail, else: inspect(detail)
    "#{code}: #{detail_text}#{context_text(refusal)}"
  end

  defp context_text(%__MODULE__{subject: subject, evidence: evidence}) do
    subject_text = if is_nil(subject), do: "", else: " (subject: #{inspect(subject)})"

    evidence_text =
      if is_map(evidence) and map_size(evidence) > 0,
        do: " evidence: #{inspect(evidence, limit: 20, printable_limit: 200)}",
        else: ""

    subject_text <> evidence_text
  end

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
          | :REFUSED_UNSUPPORTED_SPARQL_FEATURE
          | :REFUSED_SENSITIVE_ATTRIBUTE_MATERIALIZATION
          | :REFUSED_ENCRYPTED_ATTRIBUTE_PROJECTION
          | :REFUSED_NON_LITERAL_DATATYPE
          | :REFUSED_CHANGESET_CONFLICT
          | :REFUSED_MANIFEST_GENERATION
          | :REFUSED_RESOURCE_BOUND
          | :REFUSED_RESULT_LIMIT_EXCEEDED
          | :REFUSED_TRIPLE_LIMIT_EXCEEDED
          | :REFUSED_INVALID_FEDERATION_ENVIRONMENT
          | :REFUSED_MISSING_TENANT
          | :REFUSED_INVALID_OPTION
          | :REFUSED_UNAUTHORIZED
          | :REFUSED_QUERY_TIMEOUT
          | :REFUSED_READ_FAILED
          | :REFUSED_WORKER_CRASHED
          | :REFUSED_MEMORY_LIMIT_EXCEEDED
          | :REFUSED_MISSING_SUBJECT_KEY
          | :REFUSED_INVALID_SUBJECT_IRI
          | :REFUSED_NON_INVERTIBLE_TEMPLATE
          | :REFUSED_PRIVATE_DATA_LAYER

  @type t :: %__MODULE__{
          code: code(),
          subject: term(),
          detail: String.t(),
          evidence: map(),
          class: :forbidden | :invalid | :unknown
        }

  @doc """
  Builds a refusal with the given `code`, `subject`, human-readable `detail`,
  and optional `evidence` map (default `%{}`).
  """
  @spec new(code(), term(), String.t(), map()) :: t()
  def new(code, subject, detail, evidence \\ %{}) do
    %__MODULE__{code: code, subject: subject, detail: detail, evidence: evidence, class: class_for(code)}
  end
end

defmodule AshR2RML.Mapping.JoinCondition do
  @moduledoc "Explicit child/parent join used by an R2RML reference object map."
  @enforce_keys [:child, :parent]
  defstruct [:child, :parent]
  @type t :: %__MODULE__{child: String.t(), parent: String.t()}
end

defmodule AshR2RML.Mapping.Datatype do
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

defmodule AshR2RML.Mapping.GraphMap do
  @moduledoc "Named-graph placement for a subject or predicate-object mapping."
  @enforce_keys [:strategy, :value]
  defstruct [:strategy, :value]
  @type strategy :: :constant | :template | :column
  @type t :: %__MODULE__{strategy: strategy(), value: String.t()}
end

defmodule AshR2RML.Mapping.SubjectMap do
  @moduledoc "Semantic RDF subject manufacture, independent of database identity."
  @enforce_keys [:strategy, :value]
  defstruct [:strategy, :value, term_type: :iri, graph_maps: []]
  @type strategy :: :template | :column | :constant | :blank_node
  @type term_type :: :iri | :blank_node

  @type t :: %__MODULE__{
          strategy: strategy(),
          value: String.t(),
          term_type: term_type(),
          graph_maps: [AshR2RML.Mapping.GraphMap.t()]
        }
end

defmodule AshR2RML.Mapping.ObjectMap do
  @moduledoc "Scalar RDF object manufacture for one predicate-object mapping."
  @enforce_keys [:strategy, :value]
  defstruct [:strategy, :value, :datatype, :language, term_type: :literal, graph_maps: []]
  @type strategy :: :column | :template | :constant
  @type term_type :: :literal | :iri | :blank_node

  @type t :: %__MODULE__{
          strategy: strategy(),
          value: String.t(),
          datatype: AshR2RML.Mapping.Datatype.t() | nil,
          language: String.t() | nil,
          term_type: term_type(),
          graph_maps: [AshR2RML.Mapping.GraphMap.t()]
        }
end

defmodule AshR2RML.Mapping.PredicateObjectMap do
  @moduledoc "RDF datatype-property mapping normalized before R2RML serialization."
  @enforce_keys [:predicate_iri, :object_map]
  defstruct [:attribute, :predicate_iri, :object_map, graph_maps: []]

  @type t :: %__MODULE__{
          attribute: atom() | nil,
          predicate_iri: String.t(),
          object_map: AshR2RML.Mapping.ObjectMap.t(),
          graph_maps: [AshR2RML.Mapping.GraphMap.t()]
        }
end

defmodule AshR2RML.Mapping.ReferenceObjectMap do
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
          joins: [AshR2RML.Mapping.JoinCondition.t()],
          graph_maps: [AshR2RML.Mapping.GraphMap.t()],
          metadata: map()
        }
end

defmodule AshR2RML.Mapping.LogicalTable do
  @moduledoc "Exactly one relational logical source: table/view name or deterministic SQL query."
  defstruct [:table_name, :sql_query, :schema]

  @type t :: %__MODULE__{
          table_name: String.t() | nil,
          sql_query: String.t() | nil,
          schema: String.t() | nil
        }
end

defmodule AshR2RML.Mapping.Resource do
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
          logical_table: AshR2RML.Mapping.LogicalTable.t(),
          subject_map: AshR2RML.Mapping.SubjectMap.t(),
          class_iris: [String.t()],
          predicate_object_maps: [AshR2RML.Mapping.PredicateObjectMap.t()],
          reference_object_maps: [AshR2RML.Mapping.ReferenceObjectMap.t()],
          graph_maps: [AshR2RML.Mapping.GraphMap.t()],
          identities: [[atom()]],
          metadata: map()
        }
end

defmodule AshR2RML.Mapping.Bundle do
  @moduledoc "Dependency-closed set of normalized resource mappings."
  defstruct resources: []
  @type t :: %__MODULE__{resources: [AshR2RML.Mapping.Resource.t()]}
end

defmodule AshR2RML.Mapping do
  @moduledoc """
  Canonical public semantic mapping IR.

  All Ash-first and ontology-first entry paths normalize into these structures
  before R2RML serialization. Renderers are forbidden from rediscovering Ash
  relationships, storage columns, semantic identities, or datatype decisions.
  """

  alias AshR2RML.Mapping.{
    Bundle,
    PredicateObjectMap,
    ReferenceObjectMap,
    Resource,
    SubjectMap,
    Validate
  }

  alias AshR2RML.Mapping.ObjectMap
  alias AshR2RML.Refusal

  @doc """
  Puts a mapping into canonical order: sorts and de-duplicates class IRIs,
  graph maps, identities, joins, and predicate/reference object maps.

  For a bundle, normalizes each resource and sorts them by `mapping_identity/1`.
  Idempotent.
  """
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
    %Bundle{
      resources:
        bundle.resources
        |> Enum.map(&normalize/1)
        |> Enum.sort_by(&mapping_identity/1)
    }
  end

  @doc """
  Validates a resource or bundle mapping via `AshR2RML.Mapping.Validate`.

  Returns `:ok` or `{:error, [%AshR2RML.Refusal{}]}`.
  """
  @spec validate(Resource.t() | Bundle.t()) :: :ok | {:error, [Refusal.t()]}
  def validate(%Resource{} = resource), do: Validate.run(resource)
  def validate(%Bundle{} = bundle), do: Validate.run(bundle)

  @doc """
  Deterministic `urn:sha256:<hex>` identity of a resource mapping, computed over
  the normalized class IRIs, logical table, and subject map.
  """
  @spec mapping_identity(Resource.t()) :: String.t()
  def mapping_identity(%Resource{} = resource) do
    normalized = normalize(resource)

    digest =
      {normalized.class_iris, normalized.logical_table, normalized.subject_map}
      |> :erlang.term_to_binary([:deterministic])
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    "urn:sha256:" <> digest
  end

  @doc """
  Sorted, de-duplicated `{field}` names in an IRI/value template; `[]` for
  non-binaries.

      iex> AshR2RML.Mapping.template_fields("http://schema.org/{b}/{a}/{b}")
      ["a", "b"]
  """
  @spec template_fields(term()) :: [String.t()]
  def template_fields(template) when is_binary(template) do
    ~r/\{([^{}]+)\}/
    |> Regex.scan(template, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.sort()
  end

  def template_fields(_), do: []

  @doc """
  Columns the subject map derives its term from: the template fields for a
  `:template` strategy, the single column for `:column`, and `[]` otherwise.
  """
  @spec subject_identity_columns(Resource.t()) :: [String.t()]
  def subject_identity_columns(%Resource{subject_map: %SubjectMap{strategy: :template, value: value}}),
    do: template_fields(value)

  def subject_identity_columns(%Resource{subject_map: %SubjectMap{strategy: :column, value: value}}),
    do: [value]

  def subject_identity_columns(_), do: []

  @doc """
  Returns true when the subject map yields a stable IRI/node per row.

  Constant absolute-IRI and blank-node subject maps are stable. Otherwise the
  subject's identity columns must be non-empty and equal, as a set, to the
  column set of one declared identity (attributes resolved through
  `metadata.attribute_columns`, defaulting to the attribute name).
  """
  @spec stable_subject_identity?(Resource.t()) :: boolean()
  def stable_subject_identity?(%Resource{subject_map: %SubjectMap{strategy: :constant, term_type: :iri, value: value}}),
    do: Validate.absolute_iri?(value)

  def stable_subject_identity?(%Resource{subject_map: %SubjectMap{term_type: :blank_node} = subject} = resource) do
    case blank_node_fields(subject) do
      # Field-less blank nodes keep their pinned behavior; only a constant blank node
      # collapses every row to one node and is never a stable identity.
      [] -> subject.strategy != :constant
      columns -> identity_backed?(resource, columns)
    end
  end

  def stable_subject_identity?(%Resource{} = resource) do
    identity_backed?(resource, subject_identity_columns(resource))
  end

  defp blank_node_fields(%SubjectMap{strategy: strategy, value: value}) when strategy in [:template, :blank_node],
    do: template_fields(value)

  defp blank_node_fields(%SubjectMap{strategy: :column, value: value}), do: [value]
  defp blank_node_fields(_), do: []

  defp identity_backed?(_resource, []), do: false

  defp identity_backed?(resource, columns) do
    wanted = MapSet.new(columns)
    Enum.any?(identity_column_sets(resource), &(MapSet.new(&1) == wanted))
  end

  defp normalize_predicate_object_map(%PredicateObjectMap{} = mapping) do
    %{mapping | graph_maps: sort_graph_maps(mapping.graph_maps), object_map: normalize_object_map(mapping.object_map)}
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

  defp normalize_subject_map(nil), do: nil
  defp normalize_subject_map(%SubjectMap{} = map), do: %{map | graph_maps: sort_graph_maps(map.graph_maps)}
  defp normalize_object_map(nil), do: nil
  defp normalize_object_map(%ObjectMap{} = map), do: %{map | graph_maps: sort_graph_maps(map.graph_maps)}

  defp sort_graph_maps(values) do
    values
    |> Enum.uniq_by(&{&1.strategy, &1.value})
    |> Enum.sort_by(&{&1.strategy, &1.value})
  end

  @doc """
  Declared identities as column-name lists, resolving attributes through
  `metadata.attribute_columns` (default: the attribute name as a string).
  """
  @spec identity_column_sets(Resource.t()) :: [[String.t()]]
  def identity_column_sets(resource) do
    columns = Map.get(resource.metadata, :attribute_columns, %{})

    Enum.map(resource.identities, fn identity ->
      Enum.map(identity, fn attribute -> Map.get(columns, attribute, to_string(attribute)) end)
    end)
  end
end
