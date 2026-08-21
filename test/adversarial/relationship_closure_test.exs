# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Adversarial.RelationshipClosureTest do
  @moduledoc """
  Hostile Adversarial Relationship Closure Test Suite.

  Exercises:
  1. belongs_to relationships (child foreign key -> parent primary key)
  2. has_one relationships (source primary key -> child foreign key)
  3. has_many relationships (source primary key -> children foreign key)
  4. many_to_many relationships through intermediate join resources
  5. Automatic dependency-closed bundle expansion
  6. Typed refusals for broken or unmapped relationship topologies:
     - REFUSED_RELATIONSHIP_TARGET_UNMAPPED
     - REFUSED_AMBIGUOUS_RELATIONSHIP
     - REFUSED_RELATIONSHIP_WITHOUT_PREDICATE
     - REFUSED_R2RML_JOIN_WITHOUT_IDENTITY
     - REFUSED_INVALID_JOIN_CONDITION
  """
  use ExUnit.Case, async: true

  alias AshR2RML.Mapping

  defmodule Company do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :name, :string, allow_nil?: false, public?: true
    end

    actions do
      defaults [:read, :create, :update, :destroy]
    end

    r2rml do
      table_name("companies")
      class("https://schema.org/Corporation")

      subject do
        template("https://example.org/company/{id}")
      end

      property(:name, "http://xmlns.com/foaf/0.1/name")
    end
  end

  defmodule Employee do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :name, :string, allow_nil?: false, public?: true
      attribute :company_id, :uuid, allow_nil?: false, public?: true
    end

    relationships do
      belongs_to :company, AshR2RML.Adversarial.RelationshipClosureTest.Company do
        source_attribute :company_id
        destination_attribute :id
        allow_nil? false
        public? true
      end

      has_one :badge, AshR2RML.Adversarial.RelationshipClosureTest.Badge do
        source_attribute :id
        destination_attribute :employee_id
        public? true
      end

      has_many :tasks, AshR2RML.Adversarial.RelationshipClosureTest.Task do
        source_attribute :id
        destination_attribute :assignee_id
        public? true
      end
    end

    actions do
      defaults [:read, :create, :update, :destroy]
    end

    r2rml do
      table_name("employees")
      class("https://schema.org/Person")

      subject do
        template("https://example.org/employee/{id}")
      end

      property(:name, "http://xmlns.com/foaf/0.1/name")
      reference(:company, "https://schema.org/worksFor")
      reference(:badge, "https://example.org/ontology/hasBadge")
      reference(:tasks, "https://example.org/ontology/assignedTask")
    end
  end

  defmodule Badge do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :badge_number, :string, allow_nil?: false, public?: true
      attribute :employee_id, :uuid, allow_nil?: false, public?: true
    end

    relationships do
      belongs_to :employee, AshR2RML.Adversarial.RelationshipClosureTest.Employee do
        source_attribute :employee_id
        destination_attribute :id
        allow_nil? false
        public? true
      end
    end

    actions do
      defaults [:read, :create, :update, :destroy]
    end

    r2rml do
      table_name("badges")
      class("https://example.org/ontology/SecurityBadge")

      subject do
        template("https://example.org/badge/{id}")
      end

      property(:badge_number, "https://example.org/ontology/badgeNumber")
      reference(:employee, "https://example.org/ontology/badgeHolder")
    end
  end

  defmodule Task do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :title, :string, allow_nil?: false, public?: true
      attribute :assignee_id, :uuid, allow_nil?: true, public?: true
    end

    relationships do
      belongs_to :assignee, AshR2RML.Adversarial.RelationshipClosureTest.Employee do
        source_attribute :assignee_id
        destination_attribute :id
        public? true
      end
    end

    actions do
      defaults [:read, :create, :update, :destroy]
    end

    r2rml do
      table_name("tasks")
      class("https://example.org/ontology/Task")

      subject do
        template("https://example.org/task/{id}")
      end

      property(:title, "http://purl.org/dc/elements/1.1/title")
      reference(:assignee, "https://example.org/ontology/assignedTo")
    end
  end

  defmodule Patient do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :name, :string, allow_nil?: false, public?: true
    end

    actions do
      defaults [:read, :create, :update, :destroy]
    end

    r2rml do
      table_name("patients")
      class("https://schema.org/Patient")

      subject do
        template("https://example.org/patient/{id}")
      end

      property(:name, "http://xmlns.com/foaf/0.1/name")
    end
  end

  defmodule Appointment do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :doctor_id, :uuid, allow_nil?: false, public?: true
      attribute :patient_id, :uuid, allow_nil?: false, public?: true
    end

    actions do
      defaults [:read, :create, :update, :destroy]
    end

    r2rml do
      table_name("appointments")
      class("https://schema.org/MedicalAppointment")

      subject do
        template("https://example.org/appointment/{id}")
      end
    end
  end

  # Many-to-Many setup: Doctor <-> Patient through Appointment
  defmodule Doctor do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :name, :string, allow_nil?: false, public?: true
    end

    relationships do
      many_to_many :patients, AshR2RML.Adversarial.RelationshipClosureTest.Patient do
        through AshR2RML.Adversarial.RelationshipClosureTest.Appointment
        source_attribute :id
        source_attribute_on_join_resource :doctor_id
        destination_attribute :id
        destination_attribute_on_join_resource :patient_id
        public? true
      end
    end

    actions do
      defaults [:read, :create, :update, :destroy]
    end

    r2rml do
      table_name("doctors")
      class("https://schema.org/Physician")

      subject do
        template("https://example.org/doctor/{id}")
      end

      property(:name, "http://xmlns.com/foaf/0.1/name")
      reference(:patients, "https://example.org/ontology/caresFor")
    end
  end

  describe "1. Standard Cardinality Mapping and Join Introspection" do
    test "correctly extracts belongs_to join condition child -> parent" do
      mapping = AshR2RML.Resource.Info.mapping!(Employee)
      ref = Enum.find(mapping.reference_object_maps, &(&1.relationship == :company))

      assert ref.parent_resource == Company
      assert ref.predicate_iri == "https://schema.org/worksFor"
      assert [%Mapping.JoinCondition{child: "company_id", parent: "id"}] = ref.joins
    end

    test "correctly extracts has_one join condition source -> child FK" do
      mapping = AshR2RML.Resource.Info.mapping!(Employee)
      ref = Enum.find(mapping.reference_object_maps, &(&1.relationship == :badge))

      assert ref.parent_resource == Badge
      assert ref.predicate_iri == "https://example.org/ontology/hasBadge"
      assert [%Mapping.JoinCondition{child: "id", parent: "employee_id"}] = ref.joins
    end

    test "correctly extracts has_many join condition source -> children FK" do
      mapping = AshR2RML.Resource.Info.mapping!(Employee)
      ref = Enum.find(mapping.reference_object_maps, &(&1.relationship == :tasks))

      assert ref.parent_resource == Task
      assert ref.predicate_iri == "https://example.org/ontology/assignedTask"
      assert [%Mapping.JoinCondition{child: "id", parent: "assignee_id"}] = ref.joins
    end

    test "correctly extracts many_to_many bridge metadata through join resource" do
      mapping = AshR2RML.Resource.Info.mapping!(Doctor)
      ref = Enum.find(mapping.reference_object_maps, &(&1.relationship == :patients))

      assert ref.parent_resource == Patient
      assert ref.metadata.kind == :many_to_many
      assert ref.metadata.through == Appointment
      assert ref.metadata.source_to_join == %Mapping.JoinCondition{child: "id", parent: "doctor_id"}
      assert ref.metadata.join_to_destination == %Mapping.JoinCondition{child: "patient_id", parent: "id"}
    end
  end

  describe "2. Closed Dependency Bundle Auto-Expansion and R2RML Rendering" do
    test "compiles Employee and automatically includes Company, Badge, and Task in bundle closure" do
      assert {:ok, %Mapping.Bundle{} = bundle} = AshR2RML.compile(Employee)

      resource_modules = Enum.map(bundle.resources, & &1.ash_resource)
      assert Employee in resource_modules
      assert Company in resource_modules
      assert Badge in resource_modules
      assert Task in resource_modules

      assert :ok = Mapping.validate(bundle)
    end

    test "renders W3C standards-valid R2RML Turtle with parent triples maps and join conditions" do
      assert {:ok, ttl} = AshR2RML.compile(Employee) |> then(fn {:ok, bundle} -> AshR2RML.render(bundle) end)

      assert ttl =~ "rr:parentTriplesMap"
      assert ttl =~ ~s(rr:child "company_id"; rr:parent "id")
      assert ttl =~ ~s(rr:child "id"; rr:parent "employee_id")
      assert ttl =~ ~s(rr:child "id"; rr:parent "assignee_id")
    end
  end

  describe "3. Hostile Falsifiers: Relationship and Topology Invalidation" do
    test "refuses bundle when reference targets an unmapped resource" do
      unmapped_res = %Mapping.Resource{
        ash_resource: :IsolatedCaller,
        logical_table: %Mapping.LogicalTable{table_name: "callers"},
        class_iris: ["https://example.org/Caller"],
        subject_map: %Mapping.SubjectMap{strategy: :template, value: "https://example.org/c/{id}", term_type: :iri},
        identities: [[:id]],
        metadata: %{attribute_columns: %{id: "id"}},
        reference_object_maps: [
          %Mapping.ReferenceObjectMap{
            relationship: :target_rel,
            predicate_iri: "https://example.org/hasTarget",
            parent_resource: :NonExistentTargetResource,
            joins: [%Mapping.JoinCondition{child: "target_id", parent: "id"}]
          }
        ]
      }

      bundle = %Mapping.Bundle{resources: [unmapped_res]}
      assert {:error, refusals} = Mapping.validate(bundle)
      assert Enum.any?(refusals, &(&1.code == :REFUSED_RELATIONSHIP_TARGET_UNMAPPED))
    end

    test "refuses relationship mapping when predicate IRI is not absolute" do
      bad_ref_res = %Mapping.Resource{
        ash_resource: :ResourceWithBadPredicate,
        logical_table: %Mapping.LogicalTable{table_name: "table_a"},
        class_iris: ["https://example.org/ClassA"],
        subject_map: %Mapping.SubjectMap{strategy: :template, value: "https://example.org/a/{id}", term_type: :iri},
        identities: [[:id]],
        metadata: %{attribute_columns: %{id: "id"}},
        reference_object_maps: [
          %Mapping.ReferenceObjectMap{
            relationship: :rel_a,
            predicate_iri: "relative_invalid_predicate",
            parent_resource: :ResourceWithBadPredicate,
            joins: [%Mapping.JoinCondition{child: "fk", parent: "id"}]
          }
        ]
      }

      assert {:error, refusals} = Mapping.validate(bad_ref_res)
      assert Enum.any?(refusals, &(&1.code == :REFUSED_RELATIONSHIP_WITHOUT_PREDICATE))
    end

    test "refuses relationship join when target triples map has no stable subject identity" do
      source_res = %Mapping.Resource{
        ash_resource: :SourceRes,
        logical_table: %Mapping.LogicalTable{table_name: "source_table"},
        class_iris: ["https://example.org/Source"],
        subject_map: %Mapping.SubjectMap{strategy: :template, value: "https://example.org/s/{id}", term_type: :iri},
        identities: [[:id]],
        metadata: %{attribute_columns: %{id: "id"}},
        reference_object_maps: [
          %Mapping.ReferenceObjectMap{
            relationship: :unstable_target,
            predicate_iri: "https://example.org/linksTo",
            parent_resource: :TargetRes,
            joins: [%Mapping.JoinCondition{child: "target_id", parent: "id"}]
          }
        ]
      }

      target_without_id = %Mapping.Resource{
        ash_resource: :TargetRes,
        logical_table: %Mapping.LogicalTable{table_name: "target_table"},
        class_iris: ["https://example.org/Target"],
        subject_map: %Mapping.SubjectMap{
          strategy: :template,
          value: "https://example.org/t/{non_key_attr}",
          term_type: :iri
        },
        identities: [[:id]],
        metadata: %{attribute_columns: %{id: "id", non_key_attr: "non_key_attr"}}
      }

      bundle = %Mapping.Bundle{resources: [source_res, target_without_id]}
      assert {:error, refusals} = Mapping.validate(bundle)
      assert Enum.any?(refusals, &(&1.code == :REFUSED_R2RML_JOIN_WITHOUT_IDENTITY))
    end

    test "refuses join condition with empty child or parent column" do
      invalid_join_res = %Mapping.Resource{
        ash_resource: :InvalidJoinRes,
        logical_table: %Mapping.LogicalTable{table_name: "valid_table"},
        class_iris: ["https://example.org/Class"],
        subject_map: %Mapping.SubjectMap{strategy: :template, value: "https://example.org/i/{id}", term_type: :iri},
        identities: [[:id]],
        metadata: %{attribute_columns: %{id: "id"}},
        reference_object_maps: [
          %Mapping.ReferenceObjectMap{
            relationship: :broken_rel,
            predicate_iri: "https://example.org/brokenRel",
            parent_resource: :InvalidJoinRes,
            joins: [%Mapping.JoinCondition{child: "", parent: "id"}]
          }
        ]
      }

      assert {:error, refusals} = Mapping.validate(invalid_join_res)
      assert Enum.any?(refusals, &(&1.code == :REFUSED_INVALID_JOIN_CONDITION))
    end
  end
end
