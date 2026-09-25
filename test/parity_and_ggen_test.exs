# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.ParityAndGgenTest do
  use ExUnit.Case, async: true

  defp profile do
    %{
      ontology_hash: "ontology:one",
      profile_hash: "profile:one",
      shacl_hash: "shacl:one",
      resources: [
        %{
          iri: "https://example.org/resource/Organization",
          class_iri: "https://www.w3.org/ns/org#Organization",
          shape_iri: "https://example.org/shapes/OrganizationShape",
          module: "Example.Organization",
          repo_module: "Example.Repo",
          table: "organizations",
          subject_template: "https://example.org/id/organization/{id}",
          identities: [%{name: :primary, keys: [:id], primary?: true}],
          attributes: [
            %{
              name: :id,
              predicate_iri: "https://example.org/ontology/id",
              datatype_iri: "http://www.w3.org/2001/XMLSchema#string",
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
              datatype_iri: "http://www.w3.org/2001/XMLSchema#string",
              min_count: 1,
              max_count: 1
            }
          ]
        }
      ]
    }
  end

  test "ggen bundle contains every projection, catalog, and machine-readable receipt" do
    assert {:ok, bundle} = AshR2RML.compile_bundle(profile())

    assert bundle.status == :PARTIAL_ALIVE
    assert Map.has_key?(bundle.files, "generated/ash/ontology_resources.ex")
    assert Map.has_key?(bundle.files, "generated/ecto/semantic_schema_migration.exs")
    assert Map.has_key?(bundle.files, "generated/sql/semantic_schema.sql")
    assert Map.has_key?(bundle.files, "priv/r2rml/mapping.ttl")
    assert Map.has_key?(bundle.files, "generated/shacl/operational-profile.ttl")
    assert Map.has_key?(bundle.files, "generated/catalog/resource-map.json")
    assert Map.has_key?(bundle.files, "receipts/semantic-compilation.json")

    receipt = bundle.files["receipts/semantic-compilation.json"]
    catalog = bundle.files["generated/catalog/resource-map.json"]

    assert receipt =~ "ontology:one"
    assert receipt =~ "constructed_not_actuated"
    assert receipt =~ "ecto_sha256"
    assert catalog =~ "Organization"
    assert catalog =~ "predicate_iri"
  end

  test "ggen bundle receipt JSON encodes {class_iri, relationship_name}-keyed storage maps" do
    # CompilationReceipt.storage_candidates/.selected_storage (see
    # AshR2RML.Compiler.storage_map/2) are keyed by {class_iri, relationship_name}
    # tuples, not plain atoms/strings. This is a real regression guard for the
    # class of bug reported against test/integration/obda_crown.exs's own
    # (test-local, now-fixed) json_term/1: a JSON encoder path exercised only by
    # relationship-less fixtures elsewhere in this file never touches this tuple
    # key shape, so it must be exercised here with a real relationship present.
    turtle = """
    @prefix sh: <http://www.w3.org/ns/shacl#> .
    @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
    @prefix ex: <https://example.com/ontology/> .
    @prefix shapes: <https://example.com/shapes/> .
    @prefix r2ml: <https://seanchatmangpt.github.io/ash_r2rml#> .

    shapes:StorageMapOrganizationShape
        a sh:NodeShape ;
        sh:targetClass ex:Organization ;
        r2ml:ashModule "ParityAndGgenTest.StorageMapOrganization" ;
        r2ml:tableName "storage_map_test_organizations" ;
        r2ml:subjectTemplate "https://example.com/id/organization/{id}" ;
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
        ] .

    shapes:StorageMapAccountShape
        a sh:NodeShape ;
        sh:targetClass ex:Account ;
        r2ml:ashModule "ParityAndGgenTest.StorageMapAccount" ;
        r2ml:tableName "storage_map_test_accounts" ;
        r2ml:subjectTemplate "https://example.com/id/account/{id}" ;
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
            sh:path ex:organizationId ;
            r2ml:ashName "organization_id" ;
            r2ml:postgresType "TEXT" ;
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

    assert {:ok, bundle} =
             AshR2RML.compile_turtle_bundle(turtle, ontology_hash: "ontology:storage-map-test")

    receipt_json = bundle.files["receipts/semantic-compilation.json"]
    assert is_binary(receipt_json)

    decoded = Jason.decode!(receipt_json)
    expected_key = "https://example.com/ontology/Account#organization"

    assert Map.has_key?(decoded["storage_candidates"], expected_key)

    assert decoded["storage_candidates"][expected_key] ==
             ["foreign_key", "join_table", "association_resource"]

    assert decoded["selected_storage"][expected_key] == "foreign_key"
  end

  test "parity comparison is multiset-based and independent of row/key ordering" do
    left = [
      %{"resource" => "urn:r:2", "account" => "urn:a:1"},
      %{"resource" => "urn:r:1", "account" => "urn:a:1"}
    ]

    right = [
      %{account: "urn:a:1", resource: "urn:r:1"},
      %{resource: "urn:r:2", account: "urn:a:1"}
    ]

    receipt =
      AshR2RML.Parity.compare(:sparql_sql, "cloud:belongsToAccount", left, right, %{
        fixture_sha256: "fixture",
        mapping_sha256: "mapping",
        left_query: "SELECT ?resource ?account WHERE { ?resource <urn:belongsToAccount> ?account }",
        right_query: "SELECT resource, account FROM resources"
      })

    assert receipt.verified?
    assert receipt.left_result_sha256 == receipt.right_result_sha256
    assert is_binary(receipt.receipt_sha256)
  end

  test "technical equivalence and cutover authority remain separate receipts" do
    assert {:ok, compilation} = AshR2RML.Compiler.compile(profile())

    sparql_sql =
      AshR2RML.Parity.compare(:sparql_sql, :organization, [%{id: "1"}], [%{"id" => "1"}])

    receipt =
      compilation.receipt
      |> AshR2RML.Compiler.attach_parity_witness(:sparql_sql, Map.from_struct(sparql_sql))

    refute AshR2RML.Compiler.cutover_ready?(receipt)
    assert receipt.cutover_authority == :UNAUTHORIZED

    authorized =
      AshR2RML.Compiler.authorize_cutover(receipt, %{
        authorized?: true,
        receipt_sha256: "authority-receipt"
      })

    assert authorized.cutover_authority == :AUTHORIZED
    assert AshR2RML.Compiler.cutover_ready?(authorized)
  end

  test "mismatched observed results never become a verified parity witness" do
    mismatch =
      AshR2RML.Parity.compare(:sparql_sql, :organization, [%{id: "1"}], [%{id: "2"}])

    refute mismatch.verified?

    assert {:ok, compilation} = AshR2RML.Compiler.compile(profile())

    receipt =
      AshR2RML.Compiler.attach_parity_witness(
        compilation.receipt,
        :sparql_sql,
        Map.from_struct(mismatch)
      )

    assert receipt.query_parity == :UNKNOWN
    assert Enum.any?(receipt.refusals, &(&1.code == :REFUSED_UNPROVEN_EQUIVALENCE))
  end
end
