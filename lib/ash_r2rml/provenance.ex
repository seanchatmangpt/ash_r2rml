# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Mapping.Provenance do
  @moduledoc """
  Pure semantic plumbing helper for W3C PROV-O provenance assertions.

  Attaches deterministic W3C PROV-O provenance predicate-object mappings
  (`prov:wasGeneratedBy`, `prov:generatedAtTime`, `prov:wasDerivedFrom`) to normalized
  `AshR2RML.Mapping.Resource` structs without runtime execution overhead.
  """

  alias AshR2RML.Mapping.{ObjectMap, PredicateObjectMap, Resource}

  @prov "http://www.w3.org/ns/prov#"
  @xsd "http://www.w3.org/2001/XMLSchema#"

  @doc "Attaches generated_at_time provenance mapping to an AshR2RML.Mapping.Resource"
  @spec attach_generated_at_time(Resource.t(), String.t() | atom()) :: Resource.t()
  def attach_generated_at_time(%Resource{predicate_object_maps: poms} = resource, column_or_attr) do
    column_str = to_string(column_or_attr)

    pom = %PredicateObjectMap{
      attribute: if(is_atom(column_or_attr), do: column_or_attr, else: nil),
      predicate_iri: @prov <> "generatedAtTime",
      object_map: %ObjectMap{
        strategy: :column,
        value: column_str,
        datatype: %AshR2RML.Mapping.Datatype{
          ash_type: :utc_datetime,
          rdf_datatype: @xsd <> "dateTime",
          storage_type: :utc_datetime
        },
        term_type: :literal
      }
    }

    %{resource | predicate_object_maps: poms ++ [pom]}
  end

  @doc "Attaches was_derived_from provenance predicate mapping referencing a parent entity IRI template"
  @spec attach_was_derived_from(Resource.t(), String.t()) :: Resource.t()
  def attach_was_derived_from(%Resource{predicate_object_maps: poms} = resource, parent_template) do
    pom = %PredicateObjectMap{
      attribute: nil,
      predicate_iri: @prov <> "wasDerivedFrom",
      object_map: %ObjectMap{
        strategy: :template,
        value: parent_template,
        term_type: :iri
      }
    }

    %{resource | predicate_object_maps: poms ++ [pom]}
  end
end
