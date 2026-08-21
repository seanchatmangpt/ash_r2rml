# SPDX-FileCopyrightText: 2026 ash_r2ml contributors <https://github.com/seanchatmangpt/ash_r2ml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2ml.RdfIngestionAndObdaTest do
  use ExUnit.Case, async: true

  alias AshR2ml.SemanticIR.Relationship

  @profile """
  @prefix sh: <http://www.w3.org/ns/shacl#> .
  @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
  @prefix ex: <https://example.com/ontology/> .
  @prefix shapes: <https://example.com/shapes/> .
  @prefix r2ml: <https://seanchatmangpt.github.io/ash_r2ml#> .

  shapes:OrganizationShape
      a sh:NodeShape ;
      sh:targetClass ex:Organization ;
      r2ml:ashModule "Example.Organization" ;
      r2ml:repoModule "Example.Repo" ;
      r2ml:tableName "organizations" ;
      r2ml:subjectTemplate "https://example.com/id/organization/{id}" ;
      r2ml:identity [
          r2ml:identityName "primary" ;
          r2ml:identityKey "id" ;
          r2ml:primaryIdentity true
      ] ;
      sh:property [
          sh:path ex:id ;
          r2ml:ashName "id" ;
          r2ml:columnName "id" ;
          r2ml:ashType "uuid" ;
          r2ml:postgresType "UUID" ;
          sh:datatype xsd:string ;
          sh:minCount 1 ;
          sh:maxCount 1
      ] ;
      sh:property [
          sh:path ex:name ;
          r2ml:ashName "name" ;
          sh:datatype xsd:string ;
          sh:minCount 1 ;
          sh:maxCount 1
      ] .

  shapes:AccountShape
      a sh:NodeShape ;
      sh:targetClass ex:Account ;
      r2ml:ashModule "Example.Account" ;
      r2ml:repoModule "Example.Repo" ;
      r2ml:tableName "accounts" ;
      r2ml:subjectTemplate "https://example.com/id/account/{id}" ;
      r2ml:identity [
          r2ml:identityName "primary" ;
          r2ml:identityKey "id" ;
          r2ml:primaryIdentity true
      ] ;
      sh:property [
          sh:path ex:id ;
          r2ml:ashName "id" ;
          r2ml:ashType "uuid" ;
          r2ml:postgresType "UUID" ;
          sh:datatype xsd:string ;
          sh:minCount 1 ;
          sh:maxCount 1
      ] ;
      sh:property [
          sh:path ex:organizationId ;
          r2ml:ashName "organization_id" ;
          r2ml:ashType "uuid" ;
          r2ml:postgresType "UUID" ;
          sh:datatype xsd:string ;
          sh:minCount 1 ;
          sh:maxCount 1
      ] ;
      sh:property [
          sh:path ex:memberOf ;
          r2ml:ashName "organization" ;
          sh:class ex:Organization ;
          sh:minCount 1 ;
          sh:maxCount 1 ;
          r2ml:storageStrategy "foreign_key" ;
          r2ml:sourceKey "organization_id" ;
          r2ml:destinationKey "id"
      ] .
  """

  test "RDF/Turtle + SHACL is ingested into the normalized profile and compiled" do
    assert {:ok, profile} = AshR2ml.ingest_turtle(@profile, ontology_hash: "ontology:test")
    assert profile.ontology_hash == "ontology:test"
    assert is_binary(profile.profile_hash)
    assert is_binary(profile.shacl_hash)
    assert length(profile.resources) == 2

    account = Enum.find(profile.resources, &(&1.module == "Example.Account"))
    assert account.class_iri == "https://example.com/ontology/Account"
    assert hd(account.identities).keys == [:id]
    assert Enum.any?(account.attributes, &(&1.name == :organization_id))

    relationship = hd(account.relationships)
    assert relationship.name == :organization
    assert relationship.storage_strategy == :foreign_key
    assert relationship.source_key == :organization_id
    assert relationship.destination_key == :id

    assert {:ok, compilation} = AshR2ml.compile_turtle(@profile)
    assert compilation.status == :PARTIAL_ALIVE
    assert compilation.ash_source =~ "defmodule Example.Account"
    assert compilation.postgres_ddl =~ ~s(FOREIGN KEY ("organization_id"))
    assert compilation.r2rml =~ "rr:parentTriplesMap <#Example_Organization>"
  end

  test "ggen can manufacture the generic bundle directly from Turtle" do
    assert {:ok, bundle} = AshR2ml.compile_turtle_bundle(@profile)
    assert Map.has_key?(bundle.files, "priv/r2rml/mapping.ttl")
    refute Map.has_key?(bundle.files, "priv/r2rml/xaas.ttl")
    assert bundle.files["generated/shacl/operational-profile.ttl"] =~ "sh:NodeShape"
  end

  test "DfCM exposes array, jsonb and computed projections without silently selecting them" do
    relationship = %Relationship{
      name: :members,
      predicate_iri: "https://example.com/ontology/member",
      source_class: "https://example.com/ontology/Organization",
      target_class: "https://example.com/ontology/Person",
      max_count: nil,
      properties: []
    }

    candidates = AshR2ml.DfCM.storage_candidates(relationship)

    assert :join_table in candidates
    assert :association_resource in candidates
    assert :array in candidates
    assert :jsonb in candidates
    assert :computed_projection in candidates

    assert {:ok, explored} = AshR2ml.DfCM.select(relationship)
    assert explored.storage_strategy == nil
    assert explored.storage_candidates == candidates

    assert {:error, refusal} =
             AshR2ml.DfCM.select(%{relationship | storage_strategy: :array})

    assert refusal.code == :REFUSED_PROJECTION_NOT_IMPLEMENTED
  end

  test "complex SHACL paths fail closed instead of being guessed" do
    turtle = """
    @prefix sh: <http://www.w3.org/ns/shacl#> .
    @prefix ex: <https://example.com/> .
    @prefix r2ml: <https://seanchatmangpt.github.io/ash_r2ml#> .

    ex:Shape a sh:NodeShape ;
      sh:targetClass ex:Thing ;
      r2ml:ashModule "Example.Thing" ;
      r2ml:tableName "things" ;
      r2ml:subjectTemplate "https://example.com/id/{id}" ;
      r2ml:identity [ r2ml:identityName "primary" ; r2ml:identityKey "id" ; r2ml:primaryIdentity true ] ;
      sh:property [
        sh:path [ sh:inversePath ex:id ] ;
        r2ml:ashName "id" ;
        sh:datatype <http://www.w3.org/2001/XMLSchema#string> ;
        sh:minCount 1 ; sh:maxCount 1
      ] .
    """

    assert {:error, refusals} = AshR2ml.ingest_turtle(turtle)
    assert Enum.any?(refusals, &(&1.code == :REFUSED_UNSUPPORTED_SHACL_PATH))
  end

  test "Ontop adapter constructs the real CLI shape while injected execution stays test-double evidence" do
    assert {:ok, {"ontop", args}} =
             AshR2ml.OBDA.Ontop.command(
               mapping_path: "mapping.ttl",
               query_path: "query.rq",
               properties_path: "postgres.properties"
             )

    assert args == [
             "query",
             "-m",
             "mapping.ttl",
             "-q",
             "query.rq",
             "-p",
             "postgres.properties"
           ]

    runner = fn "ontop", ^args, opts ->
      assert opts[:stderr_to_stdout]
      {"resource,account\nurn:r:1,urn:a:1\n", 0}
    end

    assert {:ok, observation} =
             AshR2ml.OBDA.Ontop.query(
               [
                 mapping_path: "mapping.ttl",
                 query_path: "query.rq",
                 properties_path: "postgres.properties"
               ],
               runner
             )

    assert observation.status == :PARTIAL_ALIVE
    assert observation.standing == :test_double_only
    assert observation.evidence_kind == :injected_runner
    assert observation.rows == [%{"resource" => "urn:r:1", "account" => "urn:a:1"}]
  end
end
