# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenApiBundleTest do
  @moduledoc """
  Real end-to-end verification of `AshR2RML.Ggen.compile_api_bundle/2`: the generated Ash
  resource source is not just string-matched, it is actually compiled live (`Code.eval_string/1`,
  the same pattern `test/ggen_turtle_live_test.exs` already uses) and the resulting module is
  introspected through the real `AshGraphql.Resource.Info`/`AshJsonApi.Resource.Info` APIs --
  proof the auto-derived `graphql do ... end`/`json_api do ... end` blocks are genuinely valid
  DSL, not just plausible-looking text.

  `ash_graphql`/`ash_json_api` are `:test`-only dependencies of AshR2RML itself, used solely to
  verify this generated output -- AshR2RML's own runtime never depends on them. Any consumer
  resource can already add these extensions directly, independent of AshR2RML, because Ash
  extensions compose; this bundle only auto-derives the minimal starting block from the same
  mapping IR that already drives `r2rml`.
  """
  use ExUnit.Case, async: false

  @xsd_string "http://www.w3.org/2001/XMLSchema#string"

  defp profile(module_name) do
    %{
      ontology_hash: "ontology:sha256:api-bundle",
      profile_hash: "profile:sha256:api-bundle",
      shacl_hash: "shacl:sha256:api-bundle",
      resources: [
        %{
          iri: "https://api-bundle.example/resource/Widget",
          class_iri: "https://api-bundle.example/ontology/Widget",
          shape_iri: "https://api-bundle.example/shapes/WidgetShape",
          module: module_name,
          table: "widgets",
          subject_template: "https://api-bundle.example/id/widget/{id}",
          identities: [%{name: :primary, keys: [:id], primary?: true}],
          attributes: [
            %{
              name: :id,
              column: "id",
              predicate_iri: "https://api-bundle.example/ontology/id",
              datatype_iri: @xsd_string,
              ash_type: :uuid,
              postgres_type: "UUID",
              min_count: 1,
              max_count: 1,
              nullable: false,
              identity?: true
            },
            %{
              name: :name,
              predicate_iri: "http://xmlns.com/foaf/0.1/name",
              datatype_iri: @xsd_string,
              min_count: 1,
              max_count: 1
            }
          ]
        }
      ]
    }
  end

  test "with graphql: false, json_api: false (default), no API extensions are added" do
    assert {:ok, bundle} = AshR2RML.Ggen.compile_api_bundle(profile("AshR2RML.ApiBundleTest.PlainWidget"))
    source = bundle.files["generated/ash/api_resources.ex"]
    assert is_binary(source)
    refute source =~ "AshGraphql.Resource"
    refute source =~ "AshJsonApi.Resource"
    refute source =~ "graphql do"
    refute source =~ "json_api do"
  end

  test "graphql: true auto-derives a real, compilable graphql block with the type from the mapping IR" do
    assert {:ok, bundle} =
             AshR2RML.Ggen.compile_api_bundle(profile("AshR2RML.ApiBundleTest.GraphqlWidget"), graphql: true)

    source = bundle.files["generated/ash/api_resources.ex"]
    assert source =~ "AshGraphql.Resource"
    assert source =~ "graphql do"
    refute source =~ "AshJsonApi.Resource"

    {_result, _bindings} = Code.eval_string(source)

    assert AshGraphql.Resource in Spark.extensions(AshR2RML.ApiBundleTest.GraphqlWidget)
    assert AshGraphql.Resource.Info.type(AshR2RML.ApiBundleTest.GraphqlWidget) == :graphql_widget
  end

  test "json_api: true auto-derives a real, compilable json_api block with the type from the mapping IR" do
    assert {:ok, bundle} =
             AshR2RML.Ggen.compile_api_bundle(profile("AshR2RML.ApiBundleTest.JsonApiWidget"), json_api: true)

    source = bundle.files["generated/ash/api_resources.ex"]
    assert source =~ "AshJsonApi.Resource"
    assert source =~ "json_api do"
    refute source =~ "AshGraphql.Resource"

    {_result, _bindings} = Code.eval_string(source)

    assert AshJsonApi.Resource in Spark.extensions(AshR2RML.ApiBundleTest.JsonApiWidget)
    assert AshJsonApi.Resource.Info.type(AshR2RML.ApiBundleTest.JsonApiWidget) == "json_api_widget"
  end

  test "both graphql: true and json_api: true compose on the same resource, alongside AshR2RML" do
    assert {:ok, bundle} =
             AshR2RML.Ggen.compile_api_bundle(profile("AshR2RML.ApiBundleTest.BothWidget"),
               graphql: true,
               json_api: true
             )

    source = bundle.files["generated/ash/api_resources.ex"]
    {_result, _bindings} = Code.eval_string(source)

    extensions = Spark.extensions(AshR2RML.ApiBundleTest.BothWidget)
    assert AshR2RML in extensions
    assert AshGraphql.Resource in extensions
    assert AshJsonApi.Resource in extensions

    # The r2rml mapping is untouched by the API extensions being present.
    assert AshR2RML.Resource.Info.mapped?(AshR2RML.ApiBundleTest.BothWidget)
    {:ok, mapping} = AshR2RML.mapping_result(AshR2RML.ApiBundleTest.BothWidget)
    assert mapping.class_iris == ["https://api-bundle.example/ontology/Widget"]
  end
end
