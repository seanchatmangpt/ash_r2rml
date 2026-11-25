# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Resource do
  @moduledoc """
  Spark extension for Ash-first semantic mapping.

  The DSL carries only semantic facts that Ash/data-layer introspection cannot
  prove. Relational table names, attribute source columns, relationship
  destinations, and join attributes are derived whenever possible.
  """

  @class %Spark.Dsl.Entity{
    name: :class,
    describe: "Declares one or more rdf:type class IRIs asserted for every subject of this resource.",
    examples: [
      ~s|class "http://schema.org/Person"|,
      ~s|class ["http://schema.org/Person", "http://schema.org/Thing"]|
    ],
    args: [:iri],
    target: AshR2RML.Dsl.Class,
    identifier: :iri,
    schema: [iri: [type: {:or, [:string, {:list, :string}]}, required: true]]
  }

  @subject %Spark.Dsl.Entity{
    name: :subject,
    describe:
      "Defines how subject terms are generated: exactly one of template, column, or constant " <>
        "(blank_node term type may omit all).",
    examples: [
      ~s|subject template: "urn:uuid:{id}"|,
      ~s|subject term_type: :blank_node|
    ],
    target: AshR2RML.Dsl.Subject,
    schema: [
      template: [type: :string],
      column: [type: :atom],
      constant: [type: :string],
      term_type: [type: {:one_of, [:iri, :blank_node]}, default: :iri]
    ]
  }

  @property %Spark.Dsl.Entity{
    name: :property,
    describe: "Maps an Ash attribute to a predicate-object map with the given predicate IRI.",
    examples: [
      ~s|property :name, "http://schema.org/name"|,
      ~s|property :age, "http://schema.org/age", datatype: "http://www.w3.org/2001/XMLSchema#integer"|
    ],
    args: [:attribute, :predicate_iri],
    target: AshR2RML.Dsl.Property,
    identifier: :attribute,
    schema: [
      attribute: [type: :atom, required: true],
      predicate_iri: [type: :string, required: true],
      datatype: [type: :string],
      language: [type: :string],
      language_column: [type: :atom],
      constant: [type: :string],
      template: [type: :string],
      term_type: [type: {:one_of, [:literal, :iri, :blank_node]}, default: :literal]
    ]
  }

  @temporal %Spark.Dsl.Entity{
    name: :temporal,
    describe: "Projects start/end attributes as xsd:dateTime time:hasBeginning / time:hasEnd literals.",
    examples: [
      ~s|temporal start_attribute: :starts_at, end_attribute: :ends_at|,
      ~s|temporal start_attribute: :valid_from|
    ],
    target: AshR2RML.Dsl.Temporal,
    schema: [
      start_attribute: [type: :atom],
      end_attribute: [type: :atom]
    ]
  }

  @reference %Spark.Dsl.Entity{
    name: :reference,
    describe: "Maps an Ash relationship to a referencing object map linking subjects via a predicate IRI.",
    examples: [
      ~s|reference :company, "http://schema.org/worksFor"|,
      ~s|reference :posts, "http://schema.org/creator", direction: :incoming|
    ],
    args: [:relationship, :predicate_iri],
    target: AshR2RML.Dsl.Reference,
    identifier: :relationship,
    schema: [
      relationship: [type: :atom, required: true],
      predicate_iri: [type: :string, required: true],
      inverse_predicate: [type: :string],
      direction: [type: {:one_of, [:outgoing, :incoming]}, default: :outgoing],
      guard_class: [type: :string]
    ]
  }

  @graph %Spark.Dsl.Entity{
    name: :graph,
    describe: "Assigns generated triples to a named graph IRI, scoped to the whole resource or to the subject map.",
    examples: [
      ~s|graph "urn:uuid:00000000-0000-0000-0000-000000000001"|,
      ~s|graph "urn:uuid:00000000-0000-0000-0000-000000000001", scope: :subject|
    ],
    args: [:iri],
    target: AshR2RML.Dsl.Graph,
    identifier: :iri,
    schema: [
      iri: [type: :string, required: true],
      scope: [type: {:one_of, [:resource, :subject]}, default: :resource]
    ]
  }

  @sparql_query %Spark.Dsl.Entity{
    name: :query,
    describe: "Declares a named SPARQL query (select, construct, ask, or describe) compiled with the resource.",
    examples: [
      ~s|query :all_people, form: :select, select: [:s]|,
      ~s|query :any_person, form: :ask|
    ],
    args: [:name],
    target: AshR2RML.Dsl.SparqlQuery,
    identifier: :name,
    schema: [
      name: [type: :atom, required: true],
      form: [type: {:one_of, [:select, :construct, :ask, :describe]}, default: :select],
      select: [type: {:list, :atom}, default: []],
      where: [type: :any, default: []]
    ]
  }

  @r2rml %Spark.Dsl.Section{
    name: :r2rml,
    describe: "Semantic mapping metadata normalized into AshR2RML.Mapping",
    examples: [
      """
      r2rml do
        class "http://schema.org/Person"
        subject template: "urn:uuid:{id}"
        property :name, "http://schema.org/name"
      end
      """
    ],
    schema: [
      table_name: [type: :string],
      sql_query: [type: :string],
      schema: [type: :string]
    ],
    entities: [@class, @subject, @property, @temporal, @reference, @graph],
    singleton_entity_keys: [:subject]
  }

  @sparql %Spark.Dsl.Section{
    name: :sparql,
    describe: "Declarative SPARQL query definitions compiled with the resource",
    examples: [
      """
      sparql do
        query :all_people, form: :select, select: [:s]
      end
      """
    ],
    entities: [@sparql_query]
  }

  def section, do: @r2rml

  use Spark.Dsl.Extension,
    sections: [@r2rml, @sparql],
    transformers: [
      AshR2RML.Resource.Persist
    ],
    verifiers: [AshR2RML.Resource.Verify],
    single_extension_kinds: [:ash_r2rml]
end
