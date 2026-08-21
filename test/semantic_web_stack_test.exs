# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.SemanticWebStackTest do
  use ExUnit.Case, async: true

  @query """
  PREFIX ex: <https://example.com/>
  SELECT ?subject ?object
  WHERE { ?subject ex:rel ?object }
  """

  @profile_turtle """
  @prefix sh: <http://www.w3.org/ns/shacl#> .
  @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
  @prefix ex: <https://example.com/ontology/> .
  @prefix shapes: <https://example.com/shapes/> .
  @prefix r2ml: <https://seanchatmangpt.github.io/ash_r2rml#> .

  shapes:ThingShape
      a sh:NodeShape ;
      sh:targetClass ex:Thing ;
      r2ml:ashModule "Example.Thing" ;
      r2ml:tableName "things" ;
      r2ml:subjectTemplate "https://example.com/id/thing/{id}" ;
      r2ml:identity [
          r2ml:identityName "primary" ;
          r2ml:identityKey "id" ;
          r2ml:primaryIdentity true
      ] ;
      sh:property [
          sh:path ex:id ;
          r2ml:ashName "id" ;
          r2ml:postgresType "TEXT" ;
          sh:datatype xsd:string ;
          sh:minCount 1 ;
          sh:maxCount 1
      ] ;
      sh:property [
          sh:path ex:name ;
          r2ml:ashName "name" ;
          r2ml:postgresType "TEXT" ;
          sh:datatype xsd:string ;
          sh:minCount 1 ;
          sh:maxCount 1
      ] .
  """

  test "SPARQL.ex admission gives a stable lexical query identity" do
    assert {:ok, admitted} = AshR2RML.admit_sparql(@query)
    assert admitted.form == :select
    assert admitted.source == @query
    assert is_binary(admitted.sha256)
    assert byte_size(admitted.sha256) == 64

    assert {:ok, second} = AshR2RML.admit_sparql(@query)
    assert second.sha256 == admitted.sha256
  end

  test "local RDF execution produces parity-ready native rows" do
    graph =
      RDF.Graph.new([
        {RDF.iri("https://example.com/a"), RDF.iri("https://example.com/rel"), RDF.iri("https://example.com/b")}
      ])

    assert {:ok, observation} = AshR2RML.SPARQL.Local.query(graph, @query)
    assert observation.strategy == :local_rdf
    assert observation.evidence_kind == :in_memory_execution
    assert observation.result_kind == :bindings

    assert observation.rows == [
             %{
               "object" => "https://example.com/b",
               "subject" => "https://example.com/a"
             }
           ]

    assert is_binary(observation.result_sha256)
  end

  test "DfCM preserves local, protocol and Ontop execution candidates until selection" do
    graph = RDF.Graph.new()

    assert {:ok, plan} =
             AshR2RML.plan_sparql(@query,
               data: graph,
               endpoint: "https://example.com/sparql",
               ontop: %{mapping_path: "mapping.ttl"}
             )

    assert plan.candidates == [:local_rdf, :protocol, :ontop_cli]
    assert plan.selected == nil

    assert {:error, refusal} = AshR2RML.execute_sparql(plan)
    assert refusal.code == :REFUSED_UNPROVEN_EQUIVALENCE
    assert refusal.evidence.candidates == [:local_rdf, :protocol, :ontop_cli]

    assert {:ok, local_plan} = AshR2RML.plan_sparql(@query, data: graph, strategy: :local_rdf)
    assert local_plan.selected == :local_rdf
  end

  test "SPARQL.Client protocol results normalize through the same observation contract" do
    runner = fn %Elixir.SPARQL.Query{form: :select}, "https://example.com/sparql", _opts ->
      {:ok,
       %Elixir.SPARQL.Query.Result{
         variables: ["subject"],
         results: [%{"subject" => RDF.iri("https://example.com/a")}]
       }}
    end

    assert {:ok, observation} =
             AshR2RML.SPARQL.Protocol.query_with(
               "https://example.com/sparql",
               @query,
               [],
               runner
             )

    assert observation.strategy == :protocol
    assert observation.standing == :test_double_only
    assert observation.evidence_kind == :injected_client
    assert observation.rows == [%{"subject" => "https://example.com/a"}]
  end

  test "Turtle and JSON-LD representations converge on the same canonical mapping bundle" do
    graph = RDF.Turtle.read_string!(@profile_turtle)
    assert {:ok, jsonld} = AshR2RML.JSONLD.encode_rdf(graph, pretty: false)

    assert {:ok, turtle_bundle} = AshR2RML.compile_turtle(@profile_turtle)
    assert {:ok, jsonld_bundle} = AshR2RML.compile_jsonld(jsonld)

    assert AshR2RML.Mapping.normalize(turtle_bundle) == AshR2RML.Mapping.normalize(jsonld_bundle)

    assert {:ok, turtle_r2rml} = AshR2RML.R2RML.render(turtle_bundle)
    assert {:ok, jsonld_r2rml} = AshR2RML.R2RML.render(jsonld_bundle)
    assert turtle_r2rml == jsonld_r2rml
  end

  test "ggen manufactures the same output graph from JSON-LD input" do
    graph = RDF.Turtle.read_string!(@profile_turtle)
    assert {:ok, jsonld} = AshR2RML.JSONLD.encode_rdf(graph, pretty: false)
    assert {:ok, bundle} = AshR2RML.Ggen.compile_jsonld_bundle(jsonld)

    assert bundle.status == :PARTIAL_ALIVE
    assert Map.has_key?(bundle.files, "priv/r2rml/mapping.ttl")
    assert Map.has_key?(bundle.files, "generated/shacl/operational-profile.ttl")
    assert Map.has_key?(bundle.files, "receipts/semantic-compilation.json")
  end

  test "remote JSON-LD contexts are fail-closed unless explicitly admitted" do
    jsonld =
      Jason.encode!(%{
        "@context" => "https://example.com/context.jsonld",
        "@id" => "https://example.com/id/1"
      })

    assert {:error, refusal} = AshR2RML.JSONLD.to_rdf(jsonld)
    assert refusal.code == :REFUSED_UNPROVEN_EQUIVALENCE
    assert refusal.subject == :jsonld_context
    assert refusal.evidence.remote_contexts == ["https://example.com/context.jsonld"]
  end
end
