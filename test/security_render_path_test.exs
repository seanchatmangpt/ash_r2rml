# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.SecurityRenderPathTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Refusal

  defmodule PreDomain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      allow_unregistered? true
    end
  end

  defmodule SimpleProtected do
    use Ash.Resource,
      domain: nil,
      authorizers: [Ash.Policy.Authorizer],
      extensions: [AshR2RML.Resource]

    actions do
      defaults [:read]
    end

    policies do
      policy always() do
        authorize_if always()
      end
    end

    field_policies do
      field_policy :email do
        authorize_if always()
      end

      field_policy :* do
        authorize_if always()
      end
    end

    attributes do
      uuid_primary_key :id
      attribute :name, :string, allow_nil?: false, public?: true
      attribute :email, :string, public?: true
    end

    r2rml do
      table_name("simple_protected")
      class("http://xmlns.com/foaf/0.1/Person")
      subject template: "urn:uuid:{id}"
      property(:name, "http://xmlns.com/foaf/0.1/name")
      property(:email, "http://xmlns.com/foaf/0.1/mbox")
    end
  end

  defmodule EtsProtected do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      authorizers: [Ash.Policy.Authorizer],
      extensions: [AshR2RML.Resource]

    actions do
      defaults [:read]
    end

    policies do
      policy always() do
        authorize_if always()
      end
    end

    field_policies do
      field_policy :email do
        authorize_if always()
      end

      field_policy :* do
        authorize_if always()
      end
    end

    attributes do
      uuid_primary_key :id
      attribute :name, :string, allow_nil?: false, public?: true
      attribute :email, :string, public?: true
    end

    r2rml do
      table_name("ets_protected")
      class("http://xmlns.com/foaf/0.1/Person")
      subject template: "urn:uuid:{id}"
      property(:name, "http://xmlns.com/foaf/0.1/name")
      property(:email, "http://xmlns.com/foaf/0.1/mbox")
    end
  end

  defmodule SensitiveSubject do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    actions do
      defaults [:read]
    end

    attributes do
      uuid_primary_key :id
      attribute :national_id, :string, allow_nil?: false, public?: true, sensitive?: true
      attribute :name, :string, public?: true
    end

    identities do
      identity :by_national_id, [:national_id], pre_check_with: AshR2RML.SecurityRenderPathTest.PreDomain
    end

    r2rml do
      table_name("sensitive_subjects")
      class("https://schema.org/Person")
      subject template: "urn:uuid:{national_id}"
      property(:name, "http://xmlns.com/foaf/0.1/name")
    end
  end

  test "non-ETS layer (unknown backend) strips field-policy attributes" do
    assert AshR2RML.Introspection.backend(SimpleProtected) != :ets
    {:ok, bundle} = AshR2RML.Compiler.compile_resources(SimpleProtected)
    [mapping] = bundle.resources

    assert Enum.sort(mapping.metadata[:field_policy_excluded_attributes]) == [:email, :name]
    refute Enum.any?(mapping.predicate_object_maps, &(&1.attribute in [:email, :name]))

    {:ok, ttl} = AshR2RML.render_r2rml(SimpleProtected)
    refute ttl =~ "http://xmlns.com/foaf/0.1/mbox"
    refute ttl =~ "http://xmlns.com/foaf/0.1/name"
  end

  test "ETS layer keeps field-policy attributes (Ash-mediated reads enforce them)" do
    {:ok, bundle} = AshR2RML.Compiler.compile_resources(EtsProtected)
    [mapping] = bundle.resources

    assert Enum.any?(mapping.predicate_object_maps, &(&1.attribute == :email))
    refute Map.has_key?(mapping.metadata, :field_policy_excluded_attributes)
  end

  test "sensitive attribute in subject template refuses instead of rendering" do
    assert {:error, %Refusal{code: :REFUSED_SENSITIVE_ATTRIBUTE_MATERIALIZATION} = refusal} =
             AshR2RML.render_r2rml(SensitiveSubject)

    assert refusal.evidence.field == "national_id"
    assert refusal.evidence.where == "subject map"
  end

  test "mapping with no protected dependency is unchanged by the dependency check" do
    {:ok, mapping} = AshR2RML.mapping_result(EtsProtected)
    assert :ok = AshR2RML.Security.check_protected_dependencies(EtsProtected, mapping)
  end
end
