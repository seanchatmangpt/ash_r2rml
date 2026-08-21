# SPDX-FileCopyrightText: 2026 ash_r2ml contributors <https://github.com/seanchatmangpt/ash_r2ml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2ml do
  @moduledoc """
  Side-by-side R2RML semantic projection for Ash resources.

  `AshR2ml` is deliberately **not** an `Ash.DataLayer`. Storage and transactional
  authority remain with the resource's selected data layer (for example
  `AshPostgres.DataLayer` or the existing `AshNeo4j.DataLayer`). This extension
  adds a second, read-only semantic description of the same Ash resource so a
  relational deployment can expose a W3C R2RML virtual RDF graph without
  duplicating application state.

  The first migration phase is additive: resources may keep the existing Neo4j
  DSL and add an `r2rml` block. Cutover is a separate actuation and is never
  inferred from successful mapping generation alone.
  """

  @r2rml %Spark.Dsl.Section{
    name: :r2rml,
    describe: "W3C R2RML mapping metadata for an Ash resource",
    examples: [
      """
      r2rml do
        class_iri "https://example.com/ontology/Account"
        subject_template "https://example.com/id/account/{id}"
        table_name "accounts"
        attribute_mappings [
          {:account_number, "https://example.com/ontology/accountNumber"}
        ]
      end
      """
    ],
    schema: [
      class_iri: [
        type: :string,
        required: true,
        doc: "Absolute RDF class IRI for instances of this resource"
      ],
      subject_template: [
        type: :string,
        required: true,
        doc: "R2RML rr:template used to manufacture subject IRIs"
      ],
      table_name: [
        type: :string,
        required: false,
        doc: "Relational table or view name used as rr:tableName"
      ],
      sql_query: [
        type: :string,
        required: false,
        doc: "Logical SQL query used as rr:sqlQuery instead of table_name"
      ],
      graph_iri: [
        type: :string,
        required: false,
        doc: "Optional named graph IRI for generated triples"
      ],
      attribute_mappings: [
        type: {:list, {:tuple, [:atom, :string]}},
        required: false,
        default: [],
        doc: "Attribute-to-predicate mappings as {attribute, predicate_iri}"
      ],
      typed_attribute_mappings: [
        type: {:list, {:tuple, [:atom, :string, :string]}},
        required: false,
        default: [],
        doc: "Typed mappings as {attribute, predicate_iri, datatype_iri}"
      ],
      relationship_mappings: [
        type: {:list, {:tuple, [:atom, :string]}},
        required: false,
        default: [],
        doc: "Relationship-to-predicate mappings as {relationship, predicate_iri}"
      ]
    ]
  }

  use Spark.Dsl.Extension,
    sections: [@r2rml],
    persisters: [AshR2ml.PersistMapping],
    verifiers: [AshR2ml.VerifyMapping]

  @doc "Return the persisted semantic mapping for a resource."
  defdelegate mapping(resource), to: AshR2ml.Resource.Info

  @doc "Render a dependency-closed W3C R2RML Turtle document."
  defdelegate render_r2rml(resources), to: AshR2ml.R2RML, as: :render

  @doc "Render SHACL shapes derived from the same admitted resource mappings."
  defdelegate render_shacl(resources), to: AshR2ml.SHACL, as: :render

  @doc "Build a side-by-side validation receipt without authorizing cutover."
  defdelegate validate(resources), to: AshR2ml.Validation
end
