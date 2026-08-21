# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenAshTTLTest do
  use ExUnit.Case, async: true

  defmodule Organization do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :name, :string, allow_nil?: false, public?: true
    end

    r2rml do
      table_name("organizations")
      class("https://www.w3.org/ns/org#Organization")

      subject do
        template("https://example.test/organization/{id}")
      end

      property(:name, "http://xmlns.com/foaf/0.1/name")
    end
  end

  defmodule Account do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :account_number, :string, allow_nil?: false, public?: true
    end

    relationships do
      belongs_to :organization, Organization,
        allow_nil?: false,
        public?: true
    end

    r2rml do
      table_name("accounts")
      class("https://example.test/ontology/Account")

      subject do
        template("https://example.test/account/{id}")
      end

      property(:account_number, "https://example.test/ontology/accountNumber")
      reference(:organization, "https://www.w3.org/ns/org#memberOf")
    end
  end

  test "cloud ggen TTL is emitted from the admitted Ash dependency closure" do
    assert {:ok, result} = AshR2RML.compile_ash_ttl_bundle(Account)

    assert result.status == :PARTIAL_ALIVE
    assert result.standing == :construct_only
    assert result.source == :ash

    ontology = result.files["ontology.ttl"]
    shacl = result.files["shapes/operational-profile.ttl"]
    r2rml = result.files["r2rml/mapping.ttl"]

    assert ontology =~ "<https://example.test/ontology/Account> a rdfs:Class"
    assert ontology =~ "<https://www.w3.org/ns/org#Organization> a rdfs:Class"
    assert ontology =~ "<https://example.test/ontology/accountNumber> a rdf:Property"
    assert ontology =~ "<https://www.w3.org/ns/org#memberOf> a rdf:Property"
    assert ontology =~ "rdfs:range <https://www.w3.org/ns/org#Organization>"

    assert shacl =~ "sh:NodeShape"
    assert r2rml =~ "rr:TriplesMap"
    assert r2rml =~ ~s(rr:tableName "accounts")
    assert r2rml =~ ~s(rr:tableName "organizations")
  end

  test "Ash-emitted ggen TTL is deterministic" do
    assert {:ok, first} = AshR2RML.compile_ash_ttl_bundle(Account)
    assert {:ok, second} = AshR2RML.compile_ash_ttl_bundle(Account)

    assert first.files == second.files
    assert first.sha256 == second.sha256
  end
end
