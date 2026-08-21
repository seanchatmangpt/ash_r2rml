# SPDX-FileCopyrightText: 2026 ash_r2ml contributors <https://github.com/seanchatmangpt/ash_r2ml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2ml.OntologyFirstCompilerTest do
  use ExUnit.Case, async: true

  @xsd_string "http://www.w3.org/2001/XMLSchema#string"
  @xsd_decimal "http://www.w3.org/2001/XMLSchema#decimal"

  defp profile(overrides \\ %{}) do
    base = %{
      ontology_hash: "ontology:sha256:aaa",
      profile_hash: "profile:sha256:bbb",
      shacl_hash: "shacl:sha256:ccc",
      resources: [
        %{
          iri: "https://xaas.example/resource/Organization",
          class_iri: "https://www.w3.org/ns/org#Organization",
          shape_iri: "https://xaas.example/shapes/OrganizationShape",
          module: "Xaas.Organization",
          repo_module: "Xaas.Repo",
          table: "organizations",
          subject_template: "https://xaas.example/id/organization/{id}",
          identities: [%{name: :primary, keys: [:id], primary?: true}],
          attributes: [
            %{
              name: :id,
              column: "id",
              predicate_iri: "https://xaas.example/ontology/id",
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
        },
        %{
          iri: "https://xaas.example/resource/Account",
          class_iri: "https://spec.edmcouncil.org/fibo/ontology/FBC/FinancialPositions/FinancialPositions/Account",
          shape_iri: "https://xaas.example/shapes/AccountShape",
          module: "Xaas.Account",
          repo_module: "Xaas.Repo",
          table: "accounts",
          subject_template: "https://xaas.example/id/account/{id}",
          identities: [%{name: :primary, keys: [:id], primary?: true}],
          attributes: [
            %{
              name: :id,
              predicate_iri: "https://xaas.example/ontology/id",
              datatype_iri: @xsd_string,
              ash_type: :uuid,
              postgres_type: "UUID",
              min_count: 1,
              max_count: 1,
              nullable: false,
              identity?: true
            },
            %{
              name: :organization_id,
              predicate_iri: "https://xaas.example/ontology/organizationId",
              datatype_iri: @xsd_string,
              ash_type: :uuid,
              postgres_type: "UUID",
              min_count: 1,
              max_count: 1,
              nullable: false
            },
            %{
              name: :account_number,
              predicate_iri: "https://xaas.example/ontology/accountNumber",
              datatype_iri: @xsd_string,
              min_count: 1,
              max_count: 1
            },
            %{
              name: :balance,
              predicate_iri: "https://xaas.example/ontology/balance",
              datatype_iri: @xsd_decimal,
              min_count: 1,
              max_count: 1
            }
          ],
          relationships: [
            %{
              name: :organization,
              predicate_iri: "https://www.w3.org/ns/org#memberOf",
              source_class: "https://spec.edmcouncil.org/fibo/ontology/FBC/FinancialPositions/FinancialPositions/Account",
              target_class: "https://www.w3.org/ns/org#Organization",
              min_count: 1,
              max_count: 1,
              storage_strategy: :foreign_key,
              source_key: :organization_id,
              destination_key: :id
            }
          ],
          actions: [
            %{name: :reconcile, kind: :update, provenance: %{source: "xaas-profile"}}
          ],
          policies: [
            %{name: :account_access, effect: :authorize, odrl_iri: "http://www.w3.org/ns/odrl/2/permission"}
          ]
        }
      ]
    }

    Map.merge(base, overrides)
  end

  test "one admitted profile manufactures Ash, PostgreSQL, R2RML and SHACL projections" do
    assert {:ok, compilation} = AshR2ml.Compiler.compile(profile())

    assert compilation.status == :PARTIAL_ALIVE
    assert compilation.standing == :constructed_not_actuated

    assert compilation.ash_source =~ "defmodule Xaas.Account"
    assert compilation.ash_source =~ "data_layer: AshPostgres.DataLayer"
    assert compilation.ash_source =~ "belongs_to :organization, Xaas.Organization"

    assert compilation.postgres_ddl =~ ~s(CREATE TABLE IF NOT EXISTS "accounts")
    assert compilation.postgres_ddl =~ ~s(FOREIGN KEY ("organization_id") REFERENCES "organizations" ("id"))

    assert compilation.r2rml =~ "rr:TriplesMap"
    assert compilation.r2rml =~ "rr:parentTriplesMap <#Xaas_Organization>"
    assert compilation.r2rml =~ ~s(rr:joinCondition [ rr:child "organization_id"; rr:parent "id" ])

    assert compilation.shacl =~ "sh:targetClass <https://www.w3.org/ns/org#Organization>"
    assert compilation.shacl =~ "sh:minCount 1; sh:maxCount 1"

    assert compilation.receipt.classes_admitted == 2
    assert compilation.receipt.relationships_admitted == 1
    assert compilation.receipt.actions_admitted == 1
    assert compilation.receipt.policies_admitted == 1
    assert compilation.receipt.query_parity == :UNKNOWN
    refute AshR2ml.Compiler.cutover_ready?(compilation.receipt)
  end

  test "DfCM preserves ambiguous lawful storage candidates and refuses premature projection" do
    ambiguous =
      update_in(profile(), [:resources], fn resources ->
        Enum.map(resources, fn
          %{module: "Xaas.Account"} = account ->
            put_in(account, [:relationships, Access.at(0), :storage_strategy], nil)

          other ->
            other
        end)
      end)

    assert {:ok, ir} = AshR2ml.Compiler.explore(ambiguous)
    account = Enum.find(ir.resources, &(&1.module == "Xaas.Account"))
    relationship = hd(account.relationships)

    assert relationship.storage_strategy == nil
    assert :foreign_key in relationship.storage_candidates
    assert :association_resource in relationship.storage_candidates

    assert {:error, compilation} = AshR2ml.Compiler.compile(ambiguous)
    assert compilation.status == :REFUSED

    assert Enum.any?(compilation.refusals, fn refusal ->
             refusal.code == :REFUSED_UNPROVEN_EQUIVALENCE
           end)
  end

  test "unknown datatype is refused unless both Ash and PostgreSQL projections are supplied" do
    broken =
      update_in(profile(), [:resources], fn resources ->
        Enum.map(resources, fn
          %{module: "Xaas.Account"} = account ->
            update_in(account, [:attributes], fn attrs ->
              Enum.map(attrs, fn
                %{name: :balance} = balance ->
                  balance
                  |> Map.put(:datatype_iri, "https://example.com/datatype/Money")
                  |> Map.delete(:ash_type)
                  |> Map.delete(:postgres_type)

                other ->
                  other
              end)
            end)

          other ->
            other
        end)
      end)

    assert {:error, compilation} = AshR2ml.Compiler.compile(broken)

    assert Enum.any?(compilation.refusals, fn refusal ->
             refusal.code == :REFUSED_DATATYPE_CAST_NOT_LOSSLESS
           end)
  end

  test "projection identity is deterministic independent of input resource ordering" do
    assert {:ok, first} = AshR2ml.Compiler.compile(profile())
    reversed = update_in(profile(), [:resources], &Enum.reverse/1)
    assert {:ok, second} = AshR2ml.Compiler.compile(reversed)

    assert first.receipt.ir_sha256 == second.receipt.ir_sha256
    assert first.receipt.ash_sha256 == second.receipt.ash_sha256
    assert first.receipt.postgres_sha256 == second.receipt.postgres_sha256
    assert first.receipt.r2rml_sha256 == second.receipt.r2rml_sha256
    assert first.receipt.shacl_sha256 == second.receipt.shacl_sha256
  end

  test "cutover requires externally observed SQL/SPARQL and Neo4j/Postgres parity witnesses" do
    assert {:ok, compilation} = AshR2ml.Compiler.compile(profile())

    receipt =
      compilation.receipt
      |> AshR2ml.Compiler.attach_parity_witness(:sparql_sql, %{
        verified?: true,
        receipt_sha256: "sparql-sql-receipt"
      })
      |> AshR2ml.Compiler.attach_parity_witness(:neo4j_postgres, %{
        verified?: true,
        receipt_sha256: "neo4j-postgres-receipt"
      })

    assert receipt.query_parity == :VERIFIED
    assert receipt.neo4j_postgres_parity == :VERIFIED
    refute AshR2ml.Compiler.cutover_ready?(receipt)
    assert :cutover_authority in receipt.blocked
  end
end
