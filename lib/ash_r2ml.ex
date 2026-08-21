# SPDX-FileCopyrightText: 2026 ash_r2ml contributors <https://github.com/seanchatmangpt/ash_r2ml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2ml do
  @moduledoc """
  Side-by-side semantic projection and ontology-first compiler for Ash resources.

  `AshR2ml` is deliberately **not** an `Ash.DataLayer`. Storage and transactional
  authority remain with the resource's selected data layer (for example
  `AshPostgres.DataLayer` or the existing `AshNeo4j.DataLayer`).

  There are two additive surfaces during migration:

  * `r2rml do ... end` is the compatibility/projection DSL for existing Ash
    resources and side-by-side Neo4j validation.
  * `AshR2ml.Compiler` is the ontology-first path. It admits a closed operational
    application profile into one `AshR2ml.SemanticIR`, then manufactures Ash,
    PostgreSQL, R2RML, and SHACL projections from that same object.
  * `AshR2ml.Ingestion` parses RDF/Turtle + SHACL into that normalized profile.
  * `AshR2ml.OBDA.Ontop` is an operator-invoked external execution adapter for
    real SPARQL-over-R2RML observation; it is never invoked implicitly by compile.

  The DSL is therefore not promoted to canonical truth. In the mature path ggen
  consumes `AshR2ml.Ggen.compile_bundle/1`, writes the generated projections, and
  carries the compilation receipt. Cutover remains a separate authorized actuation
  after observed SQL/SPARQL and Neo4j/PostgreSQL parity.
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

  @doc "Return the persisted compatibility semantic mapping for an existing Ash resource."
  defdelegate mapping(resource), to: AshR2ml.Resource.Info

  @doc "Render a dependency-closed W3C R2RML Turtle document from existing Ash resources."
  defdelegate render_r2rml(resources), to: AshR2ml.R2RML, as: :render

  @doc "Render SHACL shapes derived from the same compatibility resource mappings."
  defdelegate render_shacl(resources), to: AshR2ml.SHACL, as: :render

  @doc "Build a side-by-side compatibility validation receipt without authorizing cutover."
  defdelegate validate(resources), to: AshR2ml.Validation

  @doc "Explore the ontology-first semantic IR while preserving unresolved DfCM choices."
  defdelegate explore(profile), to: AshR2ml.Compiler

  @doc "Compile one admitted operational profile into Ash/PostgreSQL/R2RML/SHACL projections."
  defdelegate compile(profile), to: AshR2ml.Compiler

  @doc "Parse Turtle/SHACL into the normalized closed application profile."
  def ingest_turtle(turtle, opts \\ []), do: AshR2ml.Ingestion.from_turtle(turtle, opts)

  @doc "Parse Turtle/SHACL and compile it through the ontology-first SemanticIR path."
  def compile_turtle(turtle, opts \\ []), do: AshR2ml.Ingestion.compile_turtle(turtle, opts)

  @doc "Build the deterministic ggen-facing output bundle without filesystem actuation."
  defdelegate compile_bundle(profile), to: AshR2ml.Ggen

  @doc "Build the deterministic ggen bundle directly from RDF/Turtle + SHACL."
  def compile_turtle_bundle(turtle, opts \\ []), do: AshR2ml.Ggen.compile_turtle_bundle(turtle, opts)
end
