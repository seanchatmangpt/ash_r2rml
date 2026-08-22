# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.SemanticTypesTest do
  use ExUnit.Case, async: true
  alias AshR2RML.{Datatype.Registry, SemanticTypes}

  @xsd "http://www.w3.org/2001/XMLSchema#"
  @rdf "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
  @skos "http://www.w3.org/2004/02/skos/core#"
  @qudt "http://qudt.org/schema/qudt/"
  @geo "http://www.opengis.net/ont/geosparql#"
  @time "http://www.w3.org/2006/time#"

  test "public providers converge on one deterministic semantic type plan" do
    iris = [@xsd <> "positiveInteger", @rdf <> "langString", @skos <> "Concept", @qudt <> "QuantityValue", @geo <> "wktLiteral", @time <> "Interval"]
    assert {:ok, first} = SemanticTypes.plan(iris)
    assert {:ok, second} = SemanticTypes.plan(Enum.reverse(iris))
    assert first.id == second.id
    assert first.status == :PARTIAL_ALIVE
    assert length(first.types) == 6
    assert :xsd in first.providers
    assert :qudt in first.providers
    assert :owl_time in first.providers
  end

  test "DfCM preserves representation alternatives until explicitly selected" do
    assert {:ok, type} = SemanticTypes.resolve(@xsd <> "positiveInteger")
    assert type.selected_representation == nil
    assert :builtin in type.representation_candidates
    assert :new_type in type.representation_candidates
    assert :custom_type in type.representation_candidates
    assert {:ok, selected} = SemanticTypes.resolve(@xsd <> "positiveInteger", selected_representation: :new_type)
    assert selected.selected_representation == :new_type
    assert selected.representation_candidates == type.representation_candidates
  end

  test "invalid representation is a typed refusal rather than an implicit fallback" do
    assert {:error, refusal} = SemanticTypes.resolve(@xsd <> "integer", selected_representation: :resource)
    assert refusal.code == :REFUSED_SEMANTIC_TYPE_REPRESENTATION
  end

  test "unknown semantic IRIs remain unsupported" do
    assert {:error, refusal} = SemanticTypes.resolve("https://example.invalid/Unknown")
    assert refusal.code == :UNSUPPORTED_SEMANTIC_TYPE
  end

  test "RDF IRI type executes storage and semantic round trip" do
    assert {:ok, type} = SemanticTypes.iri_type()
    assert {:ok, receipt} = SemanticTypes.round_trip(type, "https://example.org/id/42")
    assert receipt.loaded == "https://example.org/id/42"
    assert receipt.rdf == {:iri, "https://example.org/id/42"}
    assert receipt.restored == receipt.loaded
  end

  test "rdf:langString preserves lexical value and language" do
    assert {:ok, type} = SemanticTypes.resolve(@rdf <> "langString")
    assert {:ok, receipt} = SemanticTypes.round_trip(type, %{value: "Colour", language: "en-GB"})
    assert receipt.rdf == {:lang_literal, "Colour", "en-GB"}
    assert receipt.restored.value == "Colour"
    assert receipt.restored.language == "en-GB"
  end

  test "SKOS concepts preserve identity and scheme constraints" do
    scheme = "https://example.org/scheme/order-status"
    assert {:ok, type} = SemanticTypes.resolve(@skos <> "Concept", concept_scheme_iri: scheme)
    assert {:ok, receipt} = SemanticTypes.round_trip(type, %{iri: "https://example.org/status/shipped", scheme: scheme})
    assert receipt.rdf == {:iri, "https://example.org/status/shipped"}
    assert {:error, _} = SemanticTypes.round_trip(type, %{iri: "https://example.org/status/shipped", scheme: "https://example.org/scheme/other"})
  end

  test "QUDT quantity is a value object rather than an xsd:string collapse" do
    assert {:ok, type} = SemanticTypes.resolve(@qudt <> "QuantityValue", quantity_kind: "http://qudt.org/vocab/quantitykind/Mass", allowed_units: ["http://qudt.org/vocab/unit/KiloGM"])
    assert type.semantic_kind == :value_object
    refute :builtin in type.representation_candidates
    assert {:ok, receipt} = SemanticTypes.round_trip(type, %{value: 82.3, unit: "http://qudt.org/vocab/unit/KiloGM", quantity_kind: "http://qudt.org/vocab/quantitykind/Mass"})
    assert {:node, node} = receipt.rdf
    assert node.type == @qudt <> "QuantityValue"
    assert node.unit == "http://qudt.org/vocab/unit/KiloGM"
  end

  test "datatype registry admits semantic literals but refuses non-literal term kinds" do
    assert {:ok, datatype} = Registry.resolve(AshR2RML.Types.LangString)
    assert datatype.rdf_datatype == @rdf <> "langString"
    assert {:error, refusal} = Registry.resolve(AshR2RML.Types.IRI)
    assert refusal.code == :REFUSED_NON_LITERAL_DATATYPE
  end

  test "manifest drift distinguishes ontology-ahead, Ash-ahead and lossy changes" do
    assert {:ok, plan} = SemanticTypes.plan([@xsd <> "string", @skos <> "Concept"])
    manifest = SemanticTypes.manifest(plan)
    [first | _] = manifest.types
    observed_missing = %{manifest | types: [first]}
    assert SemanticTypes.diff(manifest, observed_missing).status == :ONTOLOGY_AHEAD

    extra = Map.put(first, :source_iri, "https://example.org/extra") |> Map.put(:name, :extra)
    observed_extra = %{manifest | types: manifest.types ++ [extra]}
    assert SemanticTypes.diff(manifest, observed_extra).status == :ASH_AHEAD

    [head | tail] = manifest.types
    observed_lossy = %{manifest | types: [Map.put(head, :datatype_iri, @xsd <> "boolean") | tail]}
    assert SemanticTypes.diff(manifest, observed_lossy).status == :LOSSY
  end

  test "generator and ggen manufacture deterministic path/content graphs without DO authority" do
    source = [%{iri: @xsd <> "positiveInteger", selected_representation: :new_type}, @skos <> "Concept"]
    assert {:ok, plan} = SemanticTypes.plan(source)
    assert {:ok, first} = AshR2RML.SemanticTypes.Generator.files(plan)
    assert {:ok, second} = AshR2RML.SemanticTypes.Generator.files(plan)
    assert first == second
    assert first["generated/ash/semantic_types.ex"] =~ "use Ash.Type.NewType"
    assert first["generated/catalog/semantic-types.json"] =~ plan.id
    assert {:ok, bundle} = AshR2RML.Ggen.compile_semantic_types_bundle(source)
    assert bundle.status == :PARTIAL_ALIVE
    assert bundle.standing == :construct_only
    assert bundle.semantic_type_plan_id == plan.id
    assert Map.has_key?(bundle.files, "receipts/semantic-type-compilation.json")
  end

  test "value objects are refused at scalar R2RML property admission" do
    assert {:ok, quantity} = SemanticTypes.resolve(@qudt <> "QuantityValue")
    assert {:error, refusal} = SemanticTypes.admit_property(quantity, :map)
    assert refusal.code == :REFUSED_SEMANTIC_TYPE_REQUIRES_RESOURCE_PROJECTION
  end
end
