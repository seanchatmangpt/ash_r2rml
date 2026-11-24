# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML do
  @moduledoc """
  Semantic mapping compiler between Ash resources and W3C R2RML.

  AshR2RML is not an Ash data layer and never owns persistence. Ash resources
  compile to `AshR2RML.Mapping.Bundle`; R2RML is then a
  deterministic projection of that normalized IR. RDF serialization and SPARQL
  execution remain explicit boundary choices rather than alternate sources of
  truth.
  """

  @r2rml %Spark.Dsl.Section{
    name: :r2rml,
    describe: "W3C R2RML mapping metadata for an Ash resource",
    schema: [
      class_iri: [type: :string, required: true],
      subject_template: [type: :string, required: true],
      table_name: [type: :string, required: false],
      sql_query: [type: :string, required: false],
      graph_iri: [type: :string, required: false],
      attribute_mappings: [type: {:list, {:tuple, [:atom, :string]}}, required: false, default: []],
      typed_attribute_mappings: [type: {:list, {:tuple, [:atom, :string, :string]}}, required: false, default: []],
      relationship_mappings: [type: {:list, {:tuple, [:atom, :string]}}, required: false, default: []]
    ]
  }

  use Spark.Dsl.Extension,
    sections: [@r2rml],
    transformers: [
      AshR2RML.PersistMapping
    ],
    verifiers: [AshR2RML.VerifyMapping]

  @doc "Compile one Ash resource into its normalized semantic mapping."
  defdelegate mapping(resource), to: AshR2RML.Resource.Info

  @doc "Compile one or more Ash resources into a closed bundle."
  defdelegate compile(resources), to: AshR2RML.Compiler, as: :compile

  @doc "Inspect normalized AshR2RML resource mapping."
  defdelegate mapping_result(resource), to: AshR2RML.Resource.Info

  @doc "Render standards-oriented R2RML Turtle from a bundle or Ash resource set."
  defdelegate render(resources_or_bundle), to: AshR2RML.R2RML

  @doc "Render standards-oriented R2RML Turtle from a bundle or Ash resource set."
  defdelegate render_r2rml(resources_or_bundle), to: AshR2RML.R2RML, as: :render

  @doc "Validate and return compilation receipt for resources."
  def validate(resources) do
    case AshR2RML.Compiler.compile(resources) do
      {:ok, %AshR2RML.Mapping.Bundle{} = bundle} ->
        {:ok, r2rml} = AshR2RML.R2RML.render(bundle)

        %AshR2RML.CompilationReceipt{
          status: :PARTIAL_ALIVE,
          standing: :constructed_not_actuated,
          mapping_sha256: AshR2RML.Compiler.sha256(bundle),
          r2rml_sha256: AshR2RML.Compiler.sha256(r2rml),
          query_parity: :UNKNOWN,
          cutover_authority: :UNAUTHORIZED,
          classes_admitted: length(bundle.resources),
          executed: [:canonical_mapping_ir, :r2rml_render],
          verified: [:canonical_mapping_ir_projection],
          blocked: [:sparql_sql_behavioral_parity, :cutover_authority],
          refusals: []
        }

      {:error, %AshR2RML.Refusal{} = refusal} ->
        %AshR2RML.CompilationReceipt{
          status: :REFUSED,
          standing: :no_cutover,
          refusals: [refusal]
        }
    end
  end
end

defmodule AshR2RML.Validation do
  @moduledoc false
  defdelegate cutover_ready?(receipt), to: AshR2RML.Compiler
end
