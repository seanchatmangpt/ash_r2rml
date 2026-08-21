# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Fortune5.EvidenceEngineTest do
  @moduledoc """
  Verifies Fortune 5 Semantic Standards, SHACL Operational Admission Shapes,
  and Evidence Engine generator capabilities.
  """
  use ExUnit.Case, async: true

  alias AshR2RML.Fortune5.EvidenceEngine

  @profile_path Path.expand("priv/ontologies/fortune5/fortune5_profile.ttl")
  @shapes_path Path.expand("priv/ontologies/fortune5/operational_shapes.ttl")

  describe "1. W3C DXWG Application Profile Validation" do
    test "fortune5_profile.ttl parses cleanly with RDF.Turtle and binds all required standard ontologies" do
      assert File.exists?(@profile_path)
      content = File.read!(@profile_path)

      assert {:ok, graph} = RDF.Turtle.read_string(content)
      assert RDF.Graph.statement_count(graph) > 50

      # Verify bindings for all required ontologies
      required_ontologies = [
        "http://www.w3.org/ns/org#",
        "http://www.w3.org/2004/02/skos/core#",
        "http://www.w3.org/ns/odrl/2/",
        "http://purl.org/net/p-plan#",
        "http://www.w3.org/ns/sosa/",
        "http://www.w3.org/ns/ssn/",
        "http://www.w3.org/2006/time#",
        "http://qudt.org/schema/qudt/",
        "https://spdx.org/rdf/3.0.0/terms/",
        "http://www.w3.org/ns/dqv#",
        "http://www.w3.org/ns/dcat#",
        "http://www.w3.org/ns/earl#",
        "http://www.w3.org/ns/r2rml#"
      ]

      profile_iri = RDF.iri("https://enterprise.fortune5.com/profile/standards")
      is_profile_of_iri = RDF.iri("http://www.w3.org/ns/dx/prof/isProfileOf")

      for ont <- required_ontologies do
        ont_iri = RDF.iri(ont)

        assert RDF.Graph.include?(graph, {profile_iri, is_profile_of_iri, ont_iri}),
               "Expected profile to declare isProfileOf <#{ont}>"
      end
    end
  end

  describe "2. W3C SHACL Operational Admission Shapes Validation" do
    test "operational_shapes.ttl parses cleanly and defines required operational admission shapes" do
      assert File.exists?(@shapes_path)
      content = File.read!(@shapes_path)

      assert {:ok, graph} = RDF.Turtle.read_string(content)
      assert RDF.Graph.statement_count(graph) > 50

      # Verify shape nodes exist
      multi_region_shape = RDF.iri("https://enterprise.fortune5.com/shapes/MultiRegionDeploymentShape")
      latency_shape = RDF.iri("https://enterprise.fortune5.com/shapes/SLALatencyConstraintShape")
      rotation_shape = RDF.iri("https://enterprise.fortune5.com/shapes/CredentialRotationDutyShape")
      audit_shape = RDF.iri("https://enterprise.fortune5.com/shapes/AuditTrailObligationShape")
      node_shape_type = RDF.iri("http://www.w3.org/ns/shacl#NodeShape")

      assert RDF.Graph.include?(graph, {multi_region_shape, RDF.iri(RDF.NS.RDF.type()), node_shape_type})
      assert RDF.Graph.include?(graph, {latency_shape, RDF.iri(RDF.NS.RDF.type()), node_shape_type})
      assert RDF.Graph.include?(graph, {rotation_shape, RDF.iri(RDF.NS.RDF.type()), node_shape_type})
      assert RDF.Graph.include?(graph, {audit_shape, RDF.iri(RDF.NS.RDF.type()), node_shape_type})
    end
  end

  describe "3. EvidenceEngine: EARL 1.0 Assertions" do
    test "generates passed, failed, and cantTell EARL assertions" do
      for outcome <- [:passed, :failed, :cantTell] do
        assert {:ok, result} =
                 EvidenceEngine.build_earl_assertion(
                   outcome: outcome,
                   info: "Testing outcome #{outcome}"
                 )

        assert is_binary(result.turtle)
        assert {:ok, parsed_graph} = RDF.Turtle.read_string(result.turtle)
        assert RDF.Graph.statement_count(parsed_graph) >= 5

        # Check outcome triple
        outcome_iri = RDF.iri("http://www.w3.org/ns/earl##{outcome}")

        assert Enum.any?(RDF.Graph.triples(parsed_graph), fn {_s, p, o} ->
                 to_string(p) == "http://www.w3.org/ns/earl#outcome" and o == outcome_iri
               end)
      end
    end
  end

  describe "4. EvidenceEngine: SOSA Observations with QUDT Units" do
    test "generates SOSA telemetry observation with QUDT quantity value and unit" do
      assert {:ok, result} =
               EvidenceEngine.build_sosa_observation(
                 numeric_value: 18.42,
                 unit: "http://qudt.org/vocab/unit/MilliSEC"
               )

      assert is_binary(result.turtle)
      assert {:ok, parsed_graph} = RDF.Turtle.read_string(result.turtle)

      # Check SOSA observation and QUDT value presence
      assert Enum.any?(RDF.Graph.triples(parsed_graph), fn {_s, p, o} ->
               to_string(p) == "http://www.w3.org/1999/02/22-rdf-syntax-ns#type" and
                 to_string(o) == "http://www.w3.org/ns/sosa/Observation"
             end)

      assert Enum.any?(RDF.Graph.triples(parsed_graph), fn {_s, p, o} ->
               to_string(p) == "http://qudt.org/schema/qudt/numericValue" and
                 to_string(o) == "18.42"
             end)

      assert Enum.any?(RDF.Graph.triples(parsed_graph), fn {_s, p, o} ->
               to_string(p) == "http://qudt.org/schema/qudt/unit" and
                 to_string(o) == "http://qudt.org/vocab/unit/MilliSEC"
             end)
    end
  end

  describe "5. EvidenceEngine: PROV-O Lineage" do
    test "generates PROV-O execution lineage with SPDX checksum" do
      sha = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

      assert {:ok, result} =
               EvidenceEngine.build_prov_lineage(sha256: sha)

      assert is_binary(result.turtle)
      assert {:ok, parsed_graph} = RDF.Turtle.read_string(result.turtle)

      assert Enum.any?(RDF.Graph.triples(parsed_graph), fn {_s, p, o} ->
               to_string(p) == "http://www.w3.org/1999/02/22-rdf-syntax-ns#type" and
                 to_string(o) == "http://www.w3.org/ns/prov#Activity"
             end)

      assert Enum.any?(RDF.Graph.triples(parsed_graph), fn {_s, p, o} ->
               to_string(p) == "https://spdx.org/rdf/3.0.0/terms/checksumValue" and
                 to_string(o) == sha
             end)
    end
  end

  describe "6. EvidenceEngine: DCAT 3 Catalog Records" do
    test "generates DCAT 3 catalog record structure" do
      assert {:ok, result} =
               EvidenceEngine.build_dcat_catalog(
                 title: "Fortune 5 Audit Catalog",
                 byte_size: 42000
               )

      assert is_binary(result.turtle)
      assert {:ok, parsed_graph} = RDF.Turtle.read_string(result.turtle)

      assert Enum.any?(RDF.Graph.triples(parsed_graph), fn {_s, p, o} ->
               to_string(p) == "http://www.w3.org/1999/02/22-rdf-syntax-ns#type" and
                 to_string(o) == "http://www.w3.org/ns/dcat#Catalog"
             end)

      assert Enum.any?(RDF.Graph.triples(parsed_graph), fn {_s, p, o} ->
               to_string(p) == "http://www.w3.org/ns/dcat#byteSize" and
                 to_string(o) == "42000"
             end)
    end
  end

  describe "7. EvidenceEngine: IEEE OCEL 2.0 Dynamic Multigraph" do
    test "emits OCEL 2.0 multigraph and validates against AshR2RML.Telemetry.OCEL2" do
      assert {:ok, ocel_res} = EvidenceEngine.emit_ocel2_multigraph()

      assert is_list(ocel_res.events)
      assert length(ocel_res.events) == 3
      assert is_binary(ocel_res.ndjson)

      # Validation report verification
      assert ocel_res.validation.valid? == true
      assert ocel_res.validation.event_count == 3
      assert ocel_res.validation.distinct_object_count >= 5

      # State reconstruction verification
      assert is_map(ocel_res.reconstruction.objects)
      assert Map.has_key?(ocel_res.reconstruction.objects, "service:router-01")

      router_obj = Map.get(ocel_res.reconstruction.objects, "service:router-01")
      assert router_obj.type == "service"
      assert is_list(router_obj.history)
      assert length(router_obj.history) == 3
    end
  end

  describe "8. EvidenceEngine: Complete Unified Bundle" do
    test "generates unified cross-linked RDF knowledge graph and validated OCEL 2.0" do
      assert {:ok, bundle} = EvidenceEngine.build_complete_evidence_bundle()

      assert is_binary(bundle.rdf_turtle)
      assert {:ok, parsed_graph} = RDF.Turtle.read_string(bundle.rdf_turtle)
      assert RDF.Graph.statement_count(parsed_graph) > 20
      assert bundle.ocel2.validation.valid? == true
    end
  end
end
