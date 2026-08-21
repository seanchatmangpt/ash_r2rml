# SPDX-FileCopyrightText: 2026 ash_r2ml contributors <https://github.com/seanchatmangpt/ash_r2ml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2mlTest.Organization do
  use Ash.Resource,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2ml]

  r2rml do
    class_iri "http://www.w3.org/ns/org#Organization"
    subject_template "https://xaas.example/id/organization/{id}"
    table_name "organizations"
    attribute_mappings [
      {:name, "http://xmlns.com/foaf/0.1/name"}
    ]
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
  end
end

defmodule AshR2mlTest.Account do
  use Ash.Resource,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2ml]

  r2rml do
    class_iri "https://spec.edmcouncil.org/fibo/ontology/FBC/FinancialPositions/FinancialPositions/Account"
    subject_template "https://xaas.example/id/account/{id}"
    table_name "accounts"
    attribute_mappings [
      {:account_number, "https://xaas.example/ontology/accountNumber"}
    ]
    typed_attribute_mappings [
      {:balance, "https://xaas.example/ontology/balance", "http://www.w3.org/2001/XMLSchema#decimal"}
    ]
    relationship_mappings [
      {:organization, "http://www.w3.org/ns/org#memberOf"}
    ]
  end

  attributes do
    uuid_primary_key :id
    attribute :account_number, :string, allow_nil?: false, public?: true
    attribute :balance, :decimal, allow_nil?: false, public?: true
  end

  relationships do
    belongs_to :organization, AshR2mlTest.Organization, allow_nil?: false, public?: true
  end
end

defmodule AshR2mlTest.Neo4jControl do
  use Ash.Resource,
    data_layer: AshNeo4j.DataLayer,
    extensions: [AshR2ml]

  neo4j do
    label :Neo4jControl
  end

  r2rml do
    class_iri "https://xaas.example/ontology/Control"
    subject_template "https://xaas.example/id/control/{id}"
    table_name "controls"
    attribute_mappings [
      {:name, "https://xaas.example/ontology/name"}
    ]
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
  end
end

defmodule AshR2mlTest do
  use ExUnit.Case, async: true

  alias AshR2mlTest.{Account, Neo4jControl, Organization}

  test "renders a dependency-closed R2RML graph from Ash relationships" do
    assert {:ok, ttl} = AshR2ml.render_r2rml(Account)

    assert ttl =~ "rr:TriplesMap"
    assert ttl =~ "rr:tableName \"accounts\""
    assert ttl =~ "rr:tableName \"organizations\""
    assert ttl =~ "rr:parentTriplesMap <#AshR2mlTest_Organization>"
    assert ttl =~ "rr:joinCondition [ rr:child \"organization_id\"; rr:parent \"id\" ]"
    assert ttl =~ "http://www.w3.org/2001/XMLSchema#decimal"
  end

  test "derives SHACL from the same mapping IR" do
    assert {:ok, ttl} = AshR2ml.render_shacl([Account, Organization])

    assert ttl =~ "sh:targetClass"
    assert ttl =~ "sh:minCount 1"
    assert ttl =~ "sh:datatype <http://www.w3.org/2001/XMLSchema#decimal>"
    assert ttl =~ "sh:class <http://www.w3.org/ns/org#Organization>"
  end

  test "coexists with the existing Neo4j control mapping without cutover" do
    assert AshR2ml.Resource.Info.mapped?(Neo4jControl)
    assert AshR2ml.Resource.Info.neo4j_control_present?(Neo4jControl)

    receipt = AshR2ml.validate(Neo4jControl)

    assert receipt.status == :PARTIAL_ALIVE
    assert receipt.query_parity == :UNKNOWN
    refute AshR2ml.Validation.cutover_ready?(receipt)
    assert :sparql_sql_behavioral_parity in receipt.blocked
    assert :cutover_authority in receipt.blocked
  end

  test "projection receipts are deterministic for the same admitted resources" do
    first = AshR2ml.validate([Account, Organization])
    second = AshR2ml.validate([Organization, Account])

    assert first.r2rml_sha256 == second.r2rml_sha256
    assert first.shacl_sha256 == second.shacl_sha256
  end
end
