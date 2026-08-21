# SPDX-FileCopyrightText: 2026 ash_r2ml contributors <https://github.com/seanchatmangpt/ash_r2ml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2ML.PublicMappingTest do
  use ExUnit.Case, async: true

  alias AshR2ML.Mapping.{
    Bundle,
    Datatype,
    JoinCondition,
    LogicalTable,
    ObjectMap,
    PredicateObjectMap,
    ReferenceObjectMap,
    Resource,
    SubjectMap
  }

  @xsd_string "http://www.w3.org/2001/XMLSchema#string"

  defp resource(name, table, class, opts \\ []) do
    id_column = Keyword.get(opts, :id_column, "id")

    %Resource{
      ash_resource: name,
      class_iris: [class],
      logical_table: %LogicalTable{table_name: table},
      subject_map: %SubjectMap{
        strategy: :template,
        value: "https://example.test/#{table}/{#{id_column}}",
        term_type: :iri
      },
      identities: [[String.to_atom(id_column)]],
      predicate_object_maps: Keyword.get(opts, :properties, []),
      reference_object_maps: Keyword.get(opts, :references, []),
      metadata: %{
        attribute_columns: Keyword.get(opts, :attribute_columns, %{String.to_atom(id_column) => id_column})
      }
    }
  end

  test "subject identity may use a mapped Ash column without emitting it as a scalar RDF predicate" do
    mapping = resource("Person", "people", "https://schema.org/Person")

    assert :ok = AshR2ML.Mapping.validate(mapping)
    assert AshR2ML.Mapping.stable_subject_identity?(mapping)
  end

  test "subject template refuses columns absent from the admitted resource mapping" do
    mapping =
      resource("Person", "people", "https://schema.org/Person")
      |> put_in([Access.key!(:subject_map), Access.key!(:value)], "https://example.test/people/{missing}")

    assert {:error, refusals} = AshR2ML.Mapping.validate(mapping)
    assert Enum.any?(refusals, &(&1.code == :REFUSED_MISSING_SUBJECT_MAP))
  end

  test "reverse has_many-style join does not require the destination join column itself to be unique" do
    account =
      resource("Account", "accounts", "https://example.test/Account",
        attribute_columns: %{id: "id", organization_id: "organization_id"}
      )

    organization =
      resource("Organization", "organizations", "https://schema.org/Organization",
        references: [
          %ReferenceObjectMap{
            relationship: :accounts,
            predicate_iri: "https://example.test/hasAccount",
            parent_resource: "Account",
            joins: [%JoinCondition{child: "id", parent: "organization_id"}],
            metadata: %{kind: :has_many, cardinality: :many}
          }
        ]
      )

    bundle = %Bundle{resources: [organization, account]}
    assert :ok = AshR2ML.Mapping.validate(bundle)
    assert {:ok, ttl} = AshR2ML.R2RML.render(bundle)
    assert ttl =~ ~s(rr:joinCondition [ rr:child "id"; rr:parent "organization_id" ])
  end

  test "many-to-many relationship renders through the actual bridge logical table" do
    organization = resource("Organization", "organizations", "https://schema.org/Organization")

    person =
      resource("Person", "people", "https://schema.org/Person",
        references: [
          %ReferenceObjectMap{
            relationship: :organizations,
            predicate_iri: "https://schema.org/memberOf",
            inverse_predicate: "https://example.test/hasMember",
            parent_resource: "Organization",
            metadata: %{
              kind: :many_to_many,
              cardinality: :many,
              through_logical_table: %LogicalTable{table_name: "memberships"},
              source_parent_column: "id",
              source_join_column: "person_id",
              destination_join_column: "organization_id",
              destination_parent_column: "id"
            }
          }
        ]
      )

    bundle = %Bundle{resources: [person, organization]}
    assert :ok = AshR2ML.Mapping.validate(bundle)
    assert {:ok, ttl} = AshR2ML.R2RML.render(bundle)

    assert ttl =~ ~s(rr:tableName "memberships")
    assert ttl =~ ~s(rr:predicate <https://schema.org/memberOf>)
    assert ttl =~ ~s(rr:predicate <https://example.test/hasMember>)
    assert ttl =~ ~s(rr:child "organization_id"; rr:parent "id")
  end

  test "scalar property renders from canonical IR without resource introspection" do
    name_property = %PredicateObjectMap{
      attribute: :name,
      predicate_iri: "http://xmlns.com/foaf/0.1/name",
      object_map: %ObjectMap{
        strategy: :column,
        value: "display_name",
        term_type: :literal,
        datatype: %Datatype{ash_type: :string, rdf_datatype: @xsd_string, storage_type: :text}
      }
    }

    mapping =
      resource("Person", "people", "https://schema.org/Person",
        properties: [name_property],
        attribute_columns: %{id: "id", name: "display_name"}
      )

    assert {:ok, ttl} = AshR2ML.R2RML.render(%Bundle{resources: [mapping]})
    assert ttl =~ ~s(rr:column "display_name")
    assert ttl =~ "rr:datatype <#{@xsd_string}>"
  end

  test "unknown custom Ash type refuses implicit stringification" do
    assert {:error, refusal} = AshR2ML.Datatype.Registry.resolve(MyApp.Money)
    assert refusal.code == :UNSUPPORTED_ASH_TYPE

    assert {:ok, datatype} =
             AshR2ML.Datatype.Registry.resolve(
               MyApp.Money,
               "https://example.test/datatype/Money",
               :decimal
             )

    assert datatype.rdf_datatype == "https://example.test/datatype/Money"
  end

  test "mapping identity is deterministic under semantic collection reordering" do
    property_a = %PredicateObjectMap{
      attribute: :name,
      predicate_iri: "https://example.test/name",
      object_map: %ObjectMap{strategy: :column, value: "name", datatype: %Datatype{rdf_datatype: @xsd_string}}
    }

    property_b = %PredicateObjectMap{
      attribute: :code,
      predicate_iri: "https://example.test/code",
      object_map: %ObjectMap{strategy: :column, value: "code", datatype: %Datatype{rdf_datatype: @xsd_string}}
    }

    first =
      resource("Thing", "things", "https://example.test/Thing",
        properties: [property_a, property_b],
        attribute_columns: %{id: "id", name: "name", code: "code"}
      )

    second = %{first | predicate_object_maps: Enum.reverse(first.predicate_object_maps)}

    assert AshR2ML.Mapping.mapping_identity(first) == AshR2ML.Mapping.mapping_identity(second)
    assert AshR2ML.Mapping.normalize(first) == AshR2ML.Mapping.normalize(second)
  end
end
