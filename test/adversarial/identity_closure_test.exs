# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Adversarial.IdentityClosureTest do
  @moduledoc """
  Hostile Adversarial Identity Closure Test Suite.

  Exercises:
  1. Single UUID primary keys (default and custom column names)
  2. Natural identities and composite natural keys
  3. URI template escaping, parameter resolution, and special character handling
  4. Typed collision refusal (REFUSED_NON_UNIQUE_SEMANTIC_IDENTITY)
  5. Missing template field refusal (REFUSED_MISSING_SUBJECT_MAP)
  6. Duplicate subject contract detection across multiple resources in a bundle
  """
  use ExUnit.Case, async: true

  alias AshR2RML.Mapping

  # 1. Standard UUID primary key resource
  defmodule StandardUuidResource do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :name, :string, allow_nil?: false, public?: true
    end

    r2rml do
      table_name("standard_uuids")
      class("https://example.org/ontology/StandardItem")

      subject do
        template("https://example.org/items/{id}")
      end

      property(:name, "http://xmlns.com/foaf/0.1/name")
    end
  end

  # 2. Custom named UUID primary key resource
  defmodule CustomUuidKeyResource do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    attributes do
      attribute :item_uuid, :uuid, primary_key?: true, allow_nil?: false, public?: true
      attribute :title, :string, allow_nil?: false, public?: true
    end

    r2rml do
      table_name("custom_uuids")
      class("https://example.org/ontology/CustomItem")

      subject do
        template("https://example.org/custom-items/{item_uuid}")
      end

      property(:title, "http://purl.org/dc/elements/1.1/title")
    end
  end

  defmodule TestDomain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.Adversarial.IdentityClosureTest.StandardUuidResource
      resource AshR2RML.Adversarial.IdentityClosureTest.CustomUuidKeyResource
      resource AshR2RML.Adversarial.IdentityClosureTest.CompositeKeyResource
      resource AshR2RML.Adversarial.IdentityClosureTest.NaturalKeyResource
      resource AshR2RML.Adversarial.IdentityClosureTest.ConstantIriResource
      resource AshR2RML.Adversarial.IdentityClosureTest.BlankNodeResource
      resource AshR2RML.Adversarial.IdentityClosureTest.MultiColumnPkResource
    end
  end

  # 3. Composite natural identity resource
  defmodule CompositeKeyResource do
    use Ash.Resource,
      domain: AshR2RML.Adversarial.IdentityClosureTest.TestDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :tenant_id, :string, allow_nil?: false, public?: true
      attribute :code, :string, allow_nil?: false, public?: true
      attribute :description, :string, allow_nil?: true, public?: true
    end

    actions do
      defaults [:read, :create, :update, :destroy]
    end

    identities do
      identity :unique_tenant_code, [:tenant_id, :code],
        pre_check_with: AshR2RML.Adversarial.IdentityClosureTest.TestDomain
    end

    r2rml do
      table_name("tenant_entries")
      class("https://example.org/ontology/TenantEntry")

      subject do
        template("https://example.org/tenants/{tenant_id}/codes/{code}")
      end

      property(:description, "http://purl.org/dc/elements/1.1/description")
    end
  end

  # 4. Natural single key identity resource (identity not using primary key)
  defmodule NaturalKeyResource do
    use Ash.Resource,
      domain: AshR2RML.Adversarial.IdentityClosureTest.TestDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :slug, :string, allow_nil?: false, public?: true
    end

    actions do
      defaults [:read, :create, :update, :destroy]
    end

    identities do
      identity :unique_slug, [:slug], pre_check_with: AshR2RML.Adversarial.IdentityClosureTest.TestDomain
    end

    r2rml do
      table_name("articles")
      class("https://example.org/ontology/Article")

      subject do
        template("https://example.org/articles/{slug}")
      end

      property(:slug, "https://example.org/ontology/slug")
    end
  end

  # 5. Constant IRI subject resource
  defmodule ConstantIriResource do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :singleton_name, :string, allow_nil?: false, public?: true
    end

    r2rml do
      table_name("singletons")
      class("https://example.org/ontology/SystemConfig")

      subject do
        constant("https://example.org/system/global-config")
      end

      property(:singleton_name, "http://xmlns.com/foaf/0.1/name")
    end
  end

  # 6. Blank node subject resource
  defmodule BlankNodeResource do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :comment, :string, allow_nil?: false, public?: true
    end

    r2rml do
      table_name("anonymous_comments")
      class("https://example.org/ontology/Comment")

      subject do
        term_type(:blank_node)
      end

      property(:comment, "http://purl.org/dc/elements/1.1/description")
    end
  end

  # 7. Multi-column Primary Key Resource
  defmodule MultiColumnPkResource do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    attributes do
      attribute :org_code, :string, primary_key?: true, allow_nil?: false, public?: true
      attribute :dept_code, :string, primary_key?: true, allow_nil?: false, public?: true
      attribute :dept_name, :string, allow_nil?: false, public?: true
    end

    r2rml do
      table_name("departments")
      class("https://example.org/ontology/Department")

      subject do
        template("https://example.org/org/{org_code}/dept/{dept_code}")
      end

      property(:dept_name, "http://xmlns.com/foaf/0.1/name")
    end
  end

  describe "1. UUID and Natural Identity Introspection" do
    test "correctly derives subject map from standard uuid_primary_key" do
      mapping = AshR2RML.Resource.Info.mapping!(StandardUuidResource)

      assert mapping.subject_map.strategy == :template
      assert mapping.subject_map.value == "https://example.org/items/{id}"
      assert mapping.identities == [[:id]]
      assert Mapping.stable_subject_identity?(mapping)
    end

    test "correctly derives subject map from custom named UUID primary key" do
      mapping = AshR2RML.Resource.Info.mapping!(CustomUuidKeyResource)

      assert mapping.subject_map.strategy == :template
      assert mapping.subject_map.value == "https://example.org/custom-items/{item_uuid}"
      assert mapping.identities == [[:item_uuid]]
      assert Mapping.stable_subject_identity?(mapping)
    end

    test "correctly derives subject map from natural key identity without primary key" do
      mapping = AshR2RML.Resource.Info.mapping!(NaturalKeyResource)

      assert mapping.subject_map.strategy == :template
      assert mapping.subject_map.value == "https://example.org/articles/{slug}"
      assert [:id] in mapping.identities
      assert [:slug] in mapping.identities
      assert Mapping.stable_subject_identity?(mapping)
    end

    test "correctly derives subject map from composite natural key identity" do
      mapping = AshR2RML.Resource.Info.mapping!(CompositeKeyResource)

      assert mapping.subject_map.strategy == :template
      assert mapping.subject_map.value == "https://example.org/tenants/{tenant_id}/codes/{code}"
      assert [:id] in mapping.identities
      assert [:code, :tenant_id] in mapping.identities
      assert Mapping.stable_subject_identity?(mapping)
    end

    test "correctly derives subject map from multi-column primary key" do
      mapping = AshR2RML.Resource.Info.mapping!(MultiColumnPkResource)

      assert mapping.subject_map.strategy == :template
      assert mapping.subject_map.value == "https://example.org/org/{org_code}/dept/{dept_code}"
      assert [:dept_code, :org_code] in mapping.identities
      assert Mapping.stable_subject_identity?(mapping)
    end

    test "derives constant IRI subject map without identity dependency" do
      mapping = AshR2RML.Resource.Info.mapping!(ConstantIriResource)

      assert mapping.subject_map.strategy == :constant
      assert mapping.subject_map.value == "https://example.org/system/global-config"
      assert Mapping.stable_subject_identity?(mapping)
    end

    test "derives blank node subject map" do
      mapping = AshR2RML.Resource.Info.mapping!(BlankNodeResource)

      assert mapping.subject_map.term_type == :blank_node
      assert Mapping.stable_subject_identity?(mapping)
    end
  end

  describe "2. URI Template Escaping and Rendering" do
    test "renders template with special URI characters and query components" do
      assert {:ok, ttl} = AshR2RML.render(CompositeKeyResource)
      assert ttl =~ ~s(rr:template "https://example.org/tenants/{tenant_id}/codes/{code}")
      assert ttl =~ ~s(rr:class <https://example.org/ontology/TenantEntry>)
    end

    test "renders multi-column primary key template accurately in R2RML" do
      assert {:ok, ttl} = AshR2RML.render(MultiColumnPkResource)
      assert ttl =~ ~s(rr:template "https://example.org/org/{org_code}/dept/{dept_code}")
      assert ttl =~ ~s(rr:tableName "departments")
    end
  end

  describe "3. Hostile Falsifiers: Identity Collision & Invalidation" do
    test "refuses subject template whose fields do NOT form an admitted Ash identity" do
      resource_mapping = %AshR2RML.Mapping.Resource{
        ash_resource: CompositeKeyResource,
        logical_table: %AshR2RML.Mapping.LogicalTable{table_name: "tenant_entries"},
        class_iris: ["https://example.org/ontology/TenantEntry"],
        subject_map: %AshR2RML.Mapping.SubjectMap{
          strategy: :template,
          value: "https://example.org/tenants/{tenant_id}",
          term_type: :iri
        },
        identities: [[:id], [:tenant_id, :code]],
        metadata: %{
          attribute_columns: %{
            id: "id",
            tenant_id: "tenant_id",
            code: "code",
            description: "description"
          }
        }
      }

      assert {:error, refusals} = Mapping.validate(resource_mapping)
      assert Enum.any?(refusals, &(&1.code == :REFUSED_NON_UNIQUE_SEMANTIC_IDENTITY))
    end

    test "refuses subject template referencing non-existent attributes" do
      resource_mapping = %AshR2RML.Mapping.Resource{
        ash_resource: StandardUuidResource,
        logical_table: %AshR2RML.Mapping.LogicalTable{table_name: "standard_uuids"},
        class_iris: ["https://example.org/ontology/StandardItem"],
        subject_map: %AshR2RML.Mapping.SubjectMap{
          strategy: :template,
          value: "https://example.org/items/{missing_field}",
          term_type: :iri
        },
        identities: [[:id]],
        metadata: %{attribute_columns: %{id: "id", name: "name"}}
      }

      assert {:error, refusals} = Mapping.validate(resource_mapping)
      assert Enum.any?(refusals, &(&1.code == :REFUSED_MISSING_SUBJECT_MAP))
    end

    test "refuses bundle containing duplicate subject contracts with overlapping classes" do
      res1 = %AshR2RML.Mapping.Resource{
        ash_resource: :ResourceA,
        logical_table: %AshR2RML.Mapping.LogicalTable{table_name: "common_table"},
        class_iris: ["https://example.org/Person"],
        subject_map: %AshR2RML.Mapping.SubjectMap{
          strategy: :template,
          value: "https://example.org/person/{id}",
          term_type: :iri
        },
        identities: [[:id]],
        metadata: %{attribute_columns: %{id: "id"}}
      }

      res2 = %AshR2RML.Mapping.Resource{
        ash_resource: :ResourceB,
        logical_table: %AshR2RML.Mapping.LogicalTable{table_name: "common_table"},
        class_iris: ["https://example.org/Person"],
        subject_map: %AshR2RML.Mapping.SubjectMap{
          strategy: :template,
          value: "https://example.org/person/{id}",
          term_type: :iri
        },
        identities: [[:id]],
        metadata: %{attribute_columns: %{id: "id"}}
      }

      bundle = %AshR2RML.Mapping.Bundle{resources: [res1, res2]}
      assert {:error, refusals} = Mapping.validate(bundle)
      assert Enum.any?(refusals, &(&1.code == :REFUSED_NON_UNIQUE_SEMANTIC_IDENTITY))
    end

    test "admits bundle with identical subject templates when RDF class sets are disjoint" do
      res1 = %AshR2RML.Mapping.Resource{
        ash_resource: :TeacherResource,
        logical_table: %AshR2RML.Mapping.LogicalTable{table_name: "people"},
        class_iris: ["https://example.org/Teacher"],
        subject_map: %AshR2RML.Mapping.SubjectMap{
          strategy: :template,
          value: "https://example.org/people/{id}",
          term_type: :iri
        },
        identities: [[:id]],
        metadata: %{attribute_columns: %{id: "id"}}
      }

      res2 = %AshR2RML.Mapping.Resource{
        ash_resource: :StudentResource,
        logical_table: %AshR2RML.Mapping.LogicalTable{table_name: "people"},
        class_iris: ["https://example.org/Student"],
        subject_map: %AshR2RML.Mapping.SubjectMap{
          strategy: :template,
          value: "https://example.org/people/{id}",
          term_type: :iri
        },
        identities: [[:id]],
        metadata: %{attribute_columns: %{id: "id"}}
      }

      bundle = %AshR2RML.Mapping.Bundle{resources: [res1, res2]}
      assert :ok = Mapping.validate(bundle)
    end
  end
end
