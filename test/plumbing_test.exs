# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.PlumbingTest.TestUser do
  use Ash.Resource,
    domain: nil,
    data_layer: Ash.DataLayer.Ets

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
    end
  end
end

defmodule AshR2RML.PlumbingTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Mapping.LogicalTable
  alias AshR2RML.Mapping.ObjectMap
  alias AshR2RML.Mapping.PredicateObjectMap
  alias AshR2RML.Mapping.Provenance
  alias AshR2RML.Mapping.Resource
  alias AshR2RML.Mapping.SubjectMap
  alias AshR2RML.PlumbingTest.TestUser
  alias AshR2RML.Refusal
  alias AshR2RML.VerifyMapping.Alignment

  defp base_resource(module, poms) do
    %Resource{
      ash_resource: module,
      logical_table: %LogicalTable{table_name: "test_users"},
      subject_map: %SubjectMap{strategy: :template, value: "https://example.org/users/{id}"},
      predicate_object_maps: poms
    }
  end

  describe "AshR2RML.Mapping.Provenance plumbing" do
    test "attach_generated_at_time/2 adds prov:generatedAtTime predicate map" do
      resource = base_resource(TestUser, [])

      updated = Provenance.attach_generated_at_time(resource, :updated_at)
      assert length(updated.predicate_object_maps) == 1

      [pom] = updated.predicate_object_maps
      assert pom.predicate_iri == "http://www.w3.org/ns/prov#generatedAtTime"
      assert pom.object_map.value == "updated_at"
    end

    test "attach_was_derived_from/2 adds prov:wasDerivedFrom IRI template map" do
      resource = base_resource(TestUser, [])

      updated = Provenance.attach_was_derived_from(resource, "https://example.org/source/{source_id}")
      assert length(updated.predicate_object_maps) == 1

      [pom] = updated.predicate_object_maps
      assert pom.predicate_iri == "http://www.w3.org/ns/prov#wasDerivedFrom"
      assert pom.object_map.strategy == :template
      assert pom.object_map.value == "https://example.org/source/{source_id}"
    end
  end

  describe "AshR2RML.VerifyMapping.Alignment plumbing" do
    test "verify/1 passes when mapped columns exist on resource attributes" do
      resource =
        base_resource(TestUser, [
          %PredicateObjectMap{
            attribute: :name,
            predicate_iri: "http://xmlns.com/foaf/0.1/name",
            object_map: %ObjectMap{strategy: :column, value: "name"}
          }
        ])

      assert :ok == Alignment.verify(resource)
    end

    test "verify/1 fails closed with REFUSED_UNKNOWN_ATTRIBUTE for unmapped columns" do
      resource =
        base_resource(TestUser, [
          %PredicateObjectMap{
            attribute: nil,
            predicate_iri: "http://xmlns.com/foaf/0.1/secret",
            object_map: %ObjectMap{strategy: :column, value: "non_existent_column"}
          }
        ])

      assert {:error, %Refusal{code: :REFUSED_UNKNOWN_ATTRIBUTE}} = Alignment.verify(resource)
    end
  end
end
