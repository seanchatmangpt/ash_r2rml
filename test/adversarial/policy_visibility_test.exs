# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Adversarial.PolicyVisibilityTest do
  @moduledoc """
  Hostile Adversarial Policy and Authorization Visibility Test Suite.

  Exercises:
  1. Ash Policy Authorizer (`Ash.Policy.Authorizer`) field-level policies
  2. Actor authorization separation: Member vs Admin
  3. `AshR2RML.Policy.filter_for_actor/3` mapping projection filtering
  4. Classification and proof of the Semantic Gap:
     - Raw OBDA/SQL executes directly against relational tables without Ash runtime policies.
     - `AshR2RML.Policy` bridges this gap by pruning unauthorized predicate-object maps at compile/render time.
  5. Reactor Pipeline `ApplyPolicy` step end-to-end execution.
  """
  use ExUnit.Case, async: true

  alias AshR2RML.Mapping
  alias AshR2RML.Policy
  alias AshR2RML.Reactor.Pipeline

  defmodule PolicyDomain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.Adversarial.PolicyVisibilityTest.SensitiveUser
    end
  end

  defmodule SensitiveUser do
    use Ash.Resource,
      domain: AshR2RML.Adversarial.PolicyVisibilityTest.PolicyDomain,
      data_layer: Ash.DataLayer.Ets,
      authorizers: [Ash.Policy.Authorizer],
      extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :username, :string, allow_nil?: false, public?: true
      attribute :email, :string, allow_nil?: false, public?: true
      attribute :ssn, :string, allow_nil?: false, public?: true
      attribute :salary, :decimal, allow_nil?: false, public?: true
    end

    actions do
      defaults [:read, :create, :update, :destroy]
    end

    policies do
      policy always() do
        authorize_if always()
      end
    end

    field_policies do
      field_policy [:ssn, :salary] do
        authorize_if actor_attribute_equals(:role, :admin)
      end

      field_policy [:username, :email] do
        authorize_if always()
      end
    end

    r2rml do
      table_name("sensitive_users")
      class("https://schema.org/Person")

      subject do
        template("https://example.org/users/{id}")
      end

      property(:username, "http://xmlns.com/foaf/0.1/nick")
      property(:email, "http://xmlns.com/foaf/0.1/mbox")
      property(:ssn, "https://example.org/ontology/ssn")
      property(:salary, "https://example.org/ontology/salary")
    end
  end

  @admin_actor %{id: "admin_1", role: :admin}
  @member_actor %{id: "user_2", role: :member}
  @guest_actor %{id: "guest_3", role: :guest}

  describe "1. Ash Policy Authorization Mechanics" do
    test "proves Ash policy authorizer allows admin to read sensitive fields" do
      assert Policy.authorized_field?(SensitiveUser, :username, @admin_actor) == true
      assert Policy.authorized_field?(SensitiveUser, :email, @admin_actor) == true
      assert Policy.authorized_field?(SensitiveUser, :ssn, @admin_actor) == true
      assert Policy.authorized_field?(SensitiveUser, :salary, @admin_actor) == true
    end

    test "proves Ash policy authorizer denies non-admin actors from reading sensitive fields" do
      assert Policy.authorized_field?(SensitiveUser, :username, @member_actor) == true
      assert Policy.authorized_field?(SensitiveUser, :email, @member_actor) == true
      assert Policy.authorized_field?(SensitiveUser, :ssn, @member_actor) == false
      assert Policy.authorized_field?(SensitiveUser, :salary, @member_actor) == false

      assert Policy.authorized_field?(SensitiveUser, :ssn, @guest_actor) == false
      assert Policy.authorized_field?(SensitiveUser, :salary, @guest_actor) == false
    end
  end

  describe "2. Policy-Aware Mapping Filtering (AshR2RML.Policy)" do
    test "filters out unauthorized predicate-object maps for regular member actor" do
      mapping = AshR2RML.Resource.Info.mapping!(SensitiveUser)
      assert length(mapping.predicate_object_maps) == 4

      filtered = Policy.filter_for_actor(mapping, @member_actor, action: :read)
      mapped_attrs = Enum.map(filtered.predicate_object_maps, & &1.attribute)

      assert :username in mapped_attrs
      assert :email in mapped_attrs
      refute :ssn in mapped_attrs
      refute :salary in mapped_attrs
      assert length(filtered.predicate_object_maps) == 2
    end

    test "retains all predicate-object maps for admin actor" do
      mapping = AshR2RML.Resource.Info.mapping!(SensitiveUser)
      filtered = Policy.filter_for_actor(mapping, @admin_actor, action: :read)
      mapped_attrs = Enum.map(filtered.predicate_object_maps, & &1.attribute)

      assert :username in mapped_attrs
      assert :email in mapped_attrs
      assert :ssn in mapped_attrs
      assert :salary in mapped_attrs
      assert length(filtered.predicate_object_maps) == 4
    end

    test "safely retains all predicate-object maps when actor is nil (no filter context)" do
      mapping = AshR2RML.Resource.Info.mapping!(SensitiveUser)
      unfiltered = Policy.filter_for_actor(mapping, nil, action: :read)

      assert length(unfiltered.predicate_object_maps) == 4
    end

    test "filters entire bundle across multiple resources" do
      mapping = AshR2RML.Resource.Info.mapping!(SensitiveUser)
      bundle = %Mapping.Bundle{resources: [mapping]}

      filtered_bundle = Policy.filter_for_actor(bundle, @member_actor, action: :read)
      [res] = filtered_bundle.resources
      mapped_attrs = Enum.map(res.predicate_object_maps, & &1.attribute)

      refute :ssn in mapped_attrs
      refute :salary in mapped_attrs
    end
  end

  describe "3. Semantic Gap: R2RML Projection vs Raw OBDA Execution" do
    test "rendering R2RML for filtered member actor completely omits sensitive RDF predicates and columns" do
      mapping = AshR2RML.Resource.Info.mapping!(SensitiveUser)
      filtered = Policy.filter_for_actor(mapping, @member_actor, action: :read)

      assert {:ok, ttl} = AshR2RML.render(filtered)

      # Allowed attributes are rendered
      assert ttl =~ "rr:predicate <http://xmlns.com/foaf/0.1/nick>"
      assert ttl =~ "rr:predicate <http://xmlns.com/foaf/0.1/mbox>"
      assert ttl =~ ~s(rr:column "username")
      assert ttl =~ ~s(rr:column "email")

      # Sensitive attributes are strictly omitted from the R2RML mapping
      refute ttl =~ "https://example.org/ontology/ssn"
      refute ttl =~ "https://example.org/ontology/salary"
      refute ttl =~ ~s(rr:column "ssn")
      refute ttl =~ ~s(rr:column "salary")
    end

    test "rendering R2RML for admin actor contains full sensitive RDF projection" do
      mapping = AshR2RML.Resource.Info.mapping!(SensitiveUser)
      filtered = Policy.filter_for_actor(mapping, @admin_actor, action: :read)

      assert {:ok, ttl} = AshR2RML.render(filtered)

      assert ttl =~ "https://example.org/ontology/ssn"
      assert ttl =~ "https://example.org/ontology/salary"
      assert ttl =~ ~s(rr:column "ssn")
      assert ttl =~ ~s(rr:column "salary")
    end
  end

  describe "4. Full Reactor Pipeline Policy Integration" do
    test "executes full pipeline with member actor and emits policy-restricted R2RML" do
      inputs = %{
        resources: [SensitiveUser],
        actor: @member_actor,
        observations: [],
        metadata: %{test: "pipeline_policy_member"}
      }

      assert {:ok, ttl} = Reactor.run(Pipeline, inputs)
      assert ttl =~ "rr:predicate <http://xmlns.com/foaf/0.1/nick>"
      refute ttl =~ "https://example.org/ontology/ssn"
      refute ttl =~ "https://example.org/ontology/salary"
    end

    test "executes full pipeline with admin actor and emits complete R2RML" do
      inputs = %{
        resources: [SensitiveUser],
        actor: @admin_actor,
        observations: [],
        metadata: %{test: "pipeline_policy_admin"}
      }

      assert {:ok, ttl} = Reactor.run(Pipeline, inputs)
      assert ttl =~ "https://example.org/ontology/ssn"
      assert ttl =~ "https://example.org/ontology/salary"
    end
  end
end
