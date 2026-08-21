# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Fortune5.GovernanceAndODRLPolicyTest do
  @moduledoc """
  Fortune 5 Enterprise Governance, ODRL 2.0 Policy Mapping & Actor Redaction Test Suite.

  Exercises:
  1. W3C ODRL 2.0 (Open Digital Rights Language) standard semantic mapping:
     - ODRL Agreements, Assets, and Parties mapped to `http://www.w3.org/ns/odrl/2/`.
  2. Field-level authorization policies with `Ash.Policy.Authorizer`.
  3. Dynamic R2RML mapping filtering via `AshR2RML.Policy.filter_for_actor/3`.
  4. Separation of authorization vs OBDA visibility (Semantic Gap Prevention):
     - Proves that unauthorized actors receive an R2RML TriplesMap with sensitive
       predicate-object maps redacted, preventing SPARQL/OBDA from exposing protected data.
  """
  use ExUnit.Case, async: true

  alias AshR2RML.Mapping
  alias AshR2RML.Mapping.Bundle
  alias AshR2RML.Policy

  # ============================================================================
  # 1. ODRL 2.0 Domain & Resources
  # ============================================================================

  defmodule ODRLDomain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.Fortune5.GovernanceAndODRLPolicyTest.ODRLPolicyAgreement
      resource AshR2RML.Fortune5.GovernanceAndODRLPolicyTest.ODRLAsset
      resource AshR2RML.Fortune5.GovernanceAndODRLPolicyTest.EmployeeGovernanceProfile
    end
  end

  defmodule ODRLAsset do
    use Ash.Resource,
      domain: AshR2RML.Fortune5.GovernanceAndODRLPolicyTest.ODRLDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :asset_urn, :string, allow_nil?: false, public?: true
      attribute :data_classification, :string, allow_nil?: false, default: "Confidential", public?: true
      attribute :retention_days, :integer, allow_nil?: false, default: 2555, public?: true
      attribute :encryption_algorithm, :string, allow_nil?: false, default: "AES-GCM-256", public?: true
    end

    identities do
      identity :asset_urn_unique, [:asset_urn], pre_check_with: AshR2RML.Fortune5.GovernanceAndODRLPolicyTest.ODRLDomain
    end

    actions do
      default_accept :*
      defaults [:read, :create, :update, :destroy]
    end

    r2rml do
      table_name("odrl_assets")
      class("http://www.w3.org/ns/odrl/2/Asset")

      subject do
        template("https://governance.fortune5.com/assets/{asset_urn}")
      end

      property(:asset_urn, "http://www.w3.org/ns/odrl/2/uid")
      property(:data_classification, "https://governance.fortune5.com/ontology/dataClassification")
      property(:retention_days, "https://governance.fortune5.com/ontology/retentionDays")
      property(:encryption_algorithm, "https://governance.fortune5.com/ontology/encryptionAlgorithm")
    end
  end

  defmodule ODRLPolicyAgreement do
    use Ash.Resource,
      domain: AshR2RML.Fortune5.GovernanceAndODRLPolicyTest.ODRLDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :policy_uid, :string, allow_nil?: false, public?: true
      attribute :action, :string, allow_nil?: false, default: "read", public?: true
      attribute :issued_date, :date, allow_nil?: false, public?: true
      attribute :asset_id, :uuid, allow_nil?: false, public?: true
    end

    identities do
      identity :policy_uid_unique, [:policy_uid],
        pre_check_with: AshR2RML.Fortune5.GovernanceAndODRLPolicyTest.ODRLDomain
    end

    relationships do
      belongs_to :asset, AshR2RML.Fortune5.GovernanceAndODRLPolicyTest.ODRLAsset do
        source_attribute :asset_id
        destination_attribute :id
        allow_nil? false
        public? true
      end
    end

    actions do
      default_accept :*
      defaults [:read, :create, :update, :destroy]
    end

    r2rml do
      table_name("odrl_policy_agreements")
      class("http://www.w3.org/ns/odrl/2/Agreement")

      subject do
        template("https://governance.fortune5.com/policies/{policy_uid}")
      end

      property(:policy_uid, "http://www.w3.org/ns/odrl/2/uid")
      property(:action, "http://www.w3.org/ns/odrl/2/action")
      property(:issued_date, "http://purl.org/dc/terms/issued")
      reference(:asset, "http://www.w3.org/ns/odrl/2/target")
    end
  end

  # ============================================================================
  # 2. Sensitive Governance Profile with Field Policies
  # ============================================================================

  defmodule EmployeeGovernanceProfile do
    use Ash.Resource,
      domain: AshR2RML.Fortune5.GovernanceAndODRLPolicyTest.ODRLDomain,
      data_layer: Ash.DataLayer.Ets,
      authorizers: [Ash.Policy.Authorizer],
      extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :employee_number, :string, allow_nil?: false, public?: true
      attribute :job_title, :string, allow_nil?: false, public?: true
      attribute :department, :string, allow_nil?: false, public?: true
      attribute :ssn_masked, :string, allow_nil?: false, public?: true
      attribute :base_compensation, :decimal, allow_nil?: false, public?: true
      attribute :stock_units, :integer, allow_nil?: false, public?: true
      attribute :whistleblower_status, :boolean, allow_nil?: false, default: false, public?: true
    end

    identities do
      identity :employee_number_unique, [:employee_number],
        pre_check_with: AshR2RML.Fortune5.GovernanceAndODRLPolicyTest.ODRLDomain
    end

    actions do
      default_accept :*
      defaults [:read, :create, :update, :destroy]
    end

    policies do
      policy always() do
        authorize_if always()
      end
    end

    field_policies do
      field_policy [:ssn_masked, :base_compensation, :stock_units, :whistleblower_status] do
        authorize_if actor_attribute_equals(:role, :executive)
      end

      field_policy [:employee_number, :job_title, :department] do
        authorize_if always()
      end
    end

    r2rml do
      table_name("employee_governance_profiles")
      class("https://governance.fortune5.com/ontology/EmployeeGovernanceProfile")

      subject do
        template("https://governance.fortune5.com/employees/{employee_number}")
      end

      property(:employee_number, "https://governance.fortune5.com/ontology/employeeNumber")
      property(:job_title, "http://xmlns.com/foaf/0.1/title")
      property(:department, "https://governance.fortune5.com/ontology/department")
      property(:ssn_masked, "https://governance.fortune5.com/ontology/ssnMasked")
      property(:base_compensation, "https://governance.fortune5.com/ontology/baseCompensation")
      property(:stock_units, "https://governance.fortune5.com/ontology/stockUnits")
      property(:whistleblower_status, "https://governance.fortune5.com/ontology/whistleblowerStatus")
    end
  end

  # Actors
  @executive_actor %{id: "exec_001", role: :executive, name: "Chief Compliance Officer"}
  @auditor_actor %{id: "auditor_002", role: :auditor, name: "Regional Internal Auditor"}
  @vendor_actor %{id: "vendor_003", role: :vendor, name: "External Payroll Contractor"}

  # ============================================================================
  # Tests
  # ============================================================================

  describe "1. W3C ODRL 2.0 Standard Policy Mapping" do
    test "compiles ODRL Asset and Policy Agreement into lawful R2RML bundle" do
      assert {:ok, %Bundle{resources: resources} = bundle} =
               AshR2RML.compile([ODRLAsset, ODRLPolicyAgreement])

      assert length(resources) == 2
      assert :ok = Mapping.validate(bundle)

      assert {:ok, turtle} = AshR2RML.render(bundle)
      assert is_binary(turtle)

      # Verify ODRL 2.0 classes and predicates
      assert String.contains?(turtle, "rr:class <http://www.w3.org/ns/odrl/2/Asset>")
      assert String.contains?(turtle, "rr:class <http://www.w3.org/ns/odrl/2/Agreement>")
      assert String.contains?(turtle, "rr:predicate <http://www.w3.org/ns/odrl/2/uid>")
      assert String.contains?(turtle, "rr:predicate <http://www.w3.org/ns/odrl/2/action>")
      assert String.contains?(turtle, "rr:predicate <http://www.w3.org/ns/odrl/2/target>")
      assert String.contains?(turtle, "rr:parentTriplesMap <#AshR2RML_Fortune5_GovernanceAndODRLPolicyTest_ODRLAsset>")
    end
  end

  describe "2. Field-Level Authorization & Actor Redaction in R2RML" do
    test "authorizes executive actor to view all sensitive governance fields" do
      assert Policy.authorized_field?(EmployeeGovernanceProfile, :employee_number, @executive_actor) == true
      assert Policy.authorized_field?(EmployeeGovernanceProfile, :job_title, @executive_actor) == true
      assert Policy.authorized_field?(EmployeeGovernanceProfile, :department, @executive_actor) == true
      assert Policy.authorized_field?(EmployeeGovernanceProfile, :ssn_masked, @executive_actor) == true
      assert Policy.authorized_field?(EmployeeGovernanceProfile, :base_compensation, @executive_actor) == true
      assert Policy.authorized_field?(EmployeeGovernanceProfile, :stock_units, @executive_actor) == true
      assert Policy.authorized_field?(EmployeeGovernanceProfile, :whistleblower_status, @executive_actor) == true
    end

    test "denies auditor and vendor actors from viewing sensitive governance fields" do
      for non_exec <- [@auditor_actor, @vendor_actor] do
        assert Policy.authorized_field?(EmployeeGovernanceProfile, :employee_number, non_exec) == true
        assert Policy.authorized_field?(EmployeeGovernanceProfile, :job_title, non_exec) == true
        assert Policy.authorized_field?(EmployeeGovernanceProfile, :department, non_exec) == true

        assert Policy.authorized_field?(EmployeeGovernanceProfile, :ssn_masked, non_exec) == false
        assert Policy.authorized_field?(EmployeeGovernanceProfile, :base_compensation, non_exec) == false
        assert Policy.authorized_field?(EmployeeGovernanceProfile, :stock_units, non_exec) == false
        assert Policy.authorized_field?(EmployeeGovernanceProfile, :whistleblower_status, non_exec) == false
      end
    end

    test "filter_for_actor/3 produces complete R2RML for Executive and redacted R2RML for Auditor" do
      assert {:ok, %Bundle{} = raw_bundle} = AshR2RML.compile(EmployeeGovernanceProfile)

      # 1. Filter for Executive Actor
      exec_bundle = Policy.filter_for_actor(raw_bundle, @executive_actor, [])
      [exec_res] = exec_bundle.resources
      exec_predicates = Enum.map(exec_res.predicate_object_maps, & &1.predicate_iri)

      assert "https://governance.fortune5.com/ontology/employeeNumber" in exec_predicates
      assert "https://governance.fortune5.com/ontology/baseCompensation" in exec_predicates
      assert "https://governance.fortune5.com/ontology/stockUnits" in exec_predicates
      assert "https://governance.fortune5.com/ontology/whistleblowerStatus" in exec_predicates

      assert {:ok, exec_turtle} = AshR2RML.render(exec_bundle)
      assert String.contains?(exec_turtle, "baseCompensation")
      assert String.contains?(exec_turtle, "whistleblowerStatus")

      # 2. Filter for Auditor Actor
      auditor_bundle = Policy.filter_for_actor(raw_bundle, @auditor_actor, [])
      [auditor_res] = auditor_bundle.resources
      auditor_predicates = Enum.map(auditor_res.predicate_object_maps, & &1.predicate_iri)

      assert "https://governance.fortune5.com/ontology/employeeNumber" in auditor_predicates
      assert "http://xmlns.com/foaf/0.1/title" in auditor_predicates
      assert "https://governance.fortune5.com/ontology/department" in auditor_predicates

      # Sensitive predicates strictly removed
      refute "https://governance.fortune5.com/ontology/ssnMasked" in auditor_predicates
      refute "https://governance.fortune5.com/ontology/baseCompensation" in auditor_predicates
      refute "https://governance.fortune5.com/ontology/stockUnits" in auditor_predicates
      refute "https://governance.fortune5.com/ontology/whistleblowerStatus" in auditor_predicates

      # Rendered Turtle for auditor contains ZERO sensitive predicate maps
      assert {:ok, auditor_turtle} = AshR2RML.render(auditor_bundle)
      assert String.contains?(auditor_turtle, "employeeNumber")
      refute String.contains?(auditor_turtle, "baseCompensation")
      refute String.contains?(auditor_turtle, "ssnMasked")
      refute String.contains?(auditor_turtle, "stockUnits")
      refute String.contains?(auditor_turtle, "whistleblowerStatus")
    end
  end

  describe "3. Separation of Authorization vs OBDA Visibility" do
    test "proves semantic gap mitigation: underlying database schema contains columns but OBDA map is pruned" do
      assert {:ok, %Bundle{} = raw_bundle} = AshR2RML.compile(EmployeeGovernanceProfile)

      # Under raw mapping (unfiltered), the mapping exposes all 7 predicate object maps
      [raw_res] = raw_bundle.resources
      assert length(raw_res.predicate_object_maps) == 7

      # Filtered for vendor actor -> only 3 predicate object maps remain
      vendor_bundle = Policy.filter_for_actor(raw_bundle, @vendor_actor, [])
      [vendor_res] = vendor_bundle.resources
      assert length(vendor_res.predicate_object_maps) == 3

      # Proves vendor OBDA triples map will never map baseCompensation or ssnMasked to SPARQL
      unauthorized_columns = ["base_compensation", "ssn_masked", "stock_units", "whistleblower_status"]

      for map <- vendor_res.predicate_object_maps do
        refute to_string(map.attribute) in unauthorized_columns
      end
    end
  end
end
