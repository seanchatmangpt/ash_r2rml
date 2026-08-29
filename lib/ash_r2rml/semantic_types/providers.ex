# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.SemanticTypes.ProviderSupport do
  @moduledoc false
  alias AshR2RML.SemanticType

  def type(provider, name, source_iri, semantic_kind, ash_type, attrs \\ []) do
    SemanticType.new(
      Keyword.merge(
        [
          name: name,
          provider: provider,
          source_iri: source_iri,
          semantic_kind: semantic_kind,
          ash_type: ash_type,
          provenance: %{authority: :public_ontology, provider: provider}
        ],
        attrs
      )
    )
  end
end

defmodule AshR2RML.SemanticTypes.XSD do
  @moduledoc "XML Schema datatype provider."
  @behaviour AshR2RML.SemanticType.Provider
  alias AshR2RML.SemanticTypes.ProviderSupport

  @ns "http://www.w3.org/2001/XMLSchema#"
  @types %{
    "string" => {:string, :text, "TEXT", []},
    "boolean" => {:boolean, :boolean, "BOOLEAN", []},
    "integer" => {:integer, :bigint, "BIGINT", []},
    "int" => {:integer, :integer, "INTEGER", []},
    "positiveInteger" => {:integer, :bigint, "BIGINT", [min: 1]},
    "nonNegativeInteger" => {:integer, :bigint, "BIGINT", [min: 0]},
    "decimal" => {:decimal, :decimal, "NUMERIC", []},
    "double" => {:float, :float, "DOUBLE PRECISION", []},
    "float" => {:float, :float, "REAL", []},
    "date" => {:date, :date, "DATE", []},
    "time" => {:time, :time, "TIME", []},
    "dateTime" => {:utc_datetime_usec, :utc_datetime_usec, "TIMESTAMPTZ", []},
    "dateTimeStamp" => {:utc_datetime_usec, :utc_datetime_usec, "TIMESTAMPTZ", []},
    "anyURI" => {:string, :text, "TEXT", []}
  }

  @impl true
  def id, do: :xsd
  @impl true
  def prefixes, do: %{xsd: @ns}
  @impl true
  def catalogue, do: Enum.map(Map.keys(@types), &(@ns <> &1))

  @impl true
  def resolve(@ns <> local = iri, opts) do
    case Map.get(@types, local) do
      {ash_type, storage, postgres, constraints} ->
        ProviderSupport.type(:xsd, name(local), iri, :literal, ash_type,
          datatype_iri: iri,
          storage_type: storage,
          postgres_type: postgres,
          constraints: constraints,
          shacl_constraints: [datatype: iri],
          selected_representation: Keyword.get(opts, :selected_representation)
        )

      nil ->
        :unknown
    end
  end

  def resolve(_, _), do: :unknown

  defp name(local), do: local |> Macro.underscore() |> String.to_atom()
end

defmodule AshR2RML.SemanticTypes.RDF do
  @moduledoc "RDF core datatype/value provider."
  @behaviour AshR2RML.SemanticType.Provider
  alias AshR2RML.SemanticTypes.ProviderSupport
  @rdf "http://www.w3.org/1999/02/22-rdf-syntax-ns#"

  @impl true
  def id, do: :rdf
  @impl true
  def prefixes, do: %{rdf: @rdf}
  @impl true
  def catalogue, do: [@rdf <> "langString", @rdf <> "JSON"]

  @impl true
  def resolve(@rdf <> "langString" = iri, opts) do
    ProviderSupport.type(:rdf, :lang_string, iri, :literal, AshR2RML.Types.LangString,
      datatype_iri: iri,
      storage_type: :map,
      postgres_type: "JSONB",
      shacl_constraints: [datatype: iri],
      selected_representation: Keyword.get(opts, :selected_representation)
    )
  end

  def resolve(@rdf <> "JSON" = iri, opts) do
    ProviderSupport.type(:rdf, :rdf_json, iri, :literal, :map,
      datatype_iri: iri,
      storage_type: :map,
      postgres_type: "JSONB",
      shacl_constraints: [datatype: iri],
      selected_representation: Keyword.get(opts, :selected_representation)
    )
  end

  def resolve(_, _), do: :unknown
end

defmodule AshR2RML.SemanticTypes.SKOS do
  @moduledoc "SKOS controlled-concept provider."
  @behaviour AshR2RML.SemanticType.Provider
  alias AshR2RML.SemanticTypes.ProviderSupport
  @skos "http://www.w3.org/2004/02/skos/core#"

  @impl true
  def id, do: :skos
  @impl true
  def prefixes, do: %{skos: @skos}
  @impl true
  def catalogue, do: [@skos <> "Concept"]

  @impl true
  def resolve(@skos <> "Concept" = iri, opts) do
    scheme = Keyword.get(opts, :concept_scheme_iri)

    ProviderSupport.type(:skos, :skos_concept, iri, :concept, AshR2RML.Types.Concept,
      class_iri: iri,
      concept_scheme_iri: scheme,
      storage_type: :map,
      postgres_type: "JSONB",
      constraints: if(scheme, do: [scheme_iri: scheme], else: []),
      shacl_constraints: [node_kind: :iri, class: iri],
      selected_representation: Keyword.get(opts, :selected_representation)
    )
  end

  def resolve(_, _), do: :unknown
end

defmodule AshR2RML.SemanticTypes.QUDT do
  @moduledoc "QUDT quantity/unit provider."
  @behaviour AshR2RML.SemanticType.Provider
  alias AshR2RML.SemanticTypes.ProviderSupport
  @qudt "http://qudt.org/schema/qudt/"

  @impl true
  def id, do: :qudt
  @impl true
  def prefixes, do: %{qudt: @qudt}
  @impl true
  def catalogue, do: [@qudt <> "QuantityValue", @qudt <> "Unit"]

  @impl true
  def resolve(@qudt <> "QuantityValue" = iri, opts) do
    ProviderSupport.type(:qudt, :quantity, iri, :value_object, AshR2RML.Types.Quantity,
      class_iri: iri,
      storage_type: :map,
      postgres_type: "JSONB",
      constraints: Keyword.take(opts, [:quantity_kind, :allowed_units]),
      shacl_constraints: [class: iri],
      selected_representation: Keyword.get(opts, :selected_representation)
    )
  end

  def resolve(@qudt <> "Unit" = iri, opts) do
    ProviderSupport.type(:qudt, :unit, iri, :iri, AshR2RML.Types.IRI,
      class_iri: iri,
      storage_type: :string,
      postgres_type: "TEXT",
      shacl_constraints: [node_kind: :iri, class: iri],
      selected_representation: Keyword.get(opts, :selected_representation)
    )
  end

  def resolve(_, _), do: :unknown
end

defmodule AshR2RML.SemanticTypes.GeoSPARQL do
  @moduledoc "OGC GeoSPARQL datatype provider."
  @behaviour AshR2RML.SemanticType.Provider
  alias AshR2RML.SemanticTypes.ProviderSupport
  @geo "http://www.opengis.net/ont/geosparql#"

  @impl true
  def id, do: :geosparql
  @impl true
  def prefixes, do: %{geo: @geo}
  @impl true
  def catalogue, do: [@geo <> "wktLiteral", @geo <> "geoJSONLiteral"]

  @impl true
  def resolve(@geo <> "wktLiteral" = iri, opts) do
    ProviderSupport.type(:geosparql, :wkt_literal, iri, :literal, AshGeo.Geometry,
      datatype_iri: iri,
      storage_type: :geometry,
      postgres_type: "GEOMETRY",
      shacl_constraints: [datatype: iri],
      selected_representation: Keyword.get(opts, :selected_representation)
    )
  end

  def resolve(@geo <> "geoJSONLiteral" = iri, opts) do
    ProviderSupport.type(:geosparql, :geojson_literal, iri, :literal, :map,
      datatype_iri: iri,
      storage_type: :map,
      postgres_type: "JSONB",
      shacl_constraints: [datatype: iri],
      selected_representation: Keyword.get(opts, :selected_representation)
    )
  end

  def resolve(_, _), do: :unknown
end

defmodule AshR2RML.SemanticTypes.OWLTime do
  @moduledoc "OWL-Time temporal entity provider preserving literal/resource alternatives."
  @behaviour AshR2RML.SemanticType.Provider
  alias AshR2RML.SemanticTypes.ProviderSupport
  @time "http://www.w3.org/2006/time#"

  @impl true
  def id, do: :owl_time
  @impl true
  def prefixes, do: %{time: @time}
  @impl true
  def catalogue, do: [@time <> "Instant", @time <> "Interval", @time <> "Duration"]

  @impl true
  def resolve(@time <> "Instant" = iri, opts) do
    ProviderSupport.type(:owl_time, :instant, iri, :value_object, :utc_datetime_usec,
      class_iri: iri,
      storage_type: :utc_datetime_usec,
      postgres_type: "TIMESTAMPTZ",
      representation_candidates: [:builtin, :custom_type, :embedded, :resource],
      shacl_constraints: [class: iri],
      selected_representation: Keyword.get(opts, :selected_representation)
    )
  end

  def resolve(@time <> "Interval" = iri, opts) do
    ProviderSupport.type(:owl_time, :interval, iri, :value_object, AshR2RML.Types.TemporalInterval,
      class_iri: iri,
      storage_type: :map,
      postgres_type: "JSONB",
      shacl_constraints: [class: iri],
      selected_representation: Keyword.get(opts, :selected_representation)
    )
  end

  def resolve(@time <> "Duration" = iri, opts) do
    ProviderSupport.type(:owl_time, :duration, iri, :value_object, :duration,
      class_iri: iri,
      storage_type: :map,
      postgres_type: "INTERVAL",
      representation_candidates: [:builtin, :custom_type, :embedded, :resource],
      shacl_constraints: [class: iri],
      selected_representation: Keyword.get(opts, :selected_representation)
    )
  end

  def resolve(_, _), do: :unknown
end
