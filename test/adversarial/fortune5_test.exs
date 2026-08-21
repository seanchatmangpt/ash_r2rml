# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Adversarial.Fortune5Test do
  @moduledoc """
  Adversarial Test Suite for Fortune 5 Ash Enterprise Factory and Saga Orchestrator.
  """
  use ExUnit.Case, async: false

  alias AshR2RML.Fortune5.AshFactory
  alias AshR2RML.Fortune5.SagaOrchestrator
  alias AshR2RML.Fortune5.Types.{CriticalityEnum, CurrencyAmount, IPAddressRange}

  alias AshR2RML.Fortune5.{
    CloudRegion,
    Cluster,
    CredentialGrant,
    DeploymentPlan,
    DeploymentPlanService,
    IncidentTicket,
    LedgerAccount,
    PaymentGateway,
    ServiceInstance
  }

  alias AshR2RML.Policy

  @admin_actor %{id: "admin-root", role: :admin}
  @security_actor %{id: "sec-officer", role: :security_officer}
  @compliance_actor %{id: "auditor-01", role: :compliance_auditor}
  @viewer_actor %{id: "viewer-01", role: :viewer}

  setup do
    SagaOrchestrator.reset_events()

    for res <- AshFactory.resources() do
      try do
        :ets.delete_all_objects(res)
      rescue
        _ -> :ok
      end
    end

    :ok
  end

  describe "1. Fortune 5 Custom Scalar Types" do
    test "CurrencyAmount type supports maps, strings, casting, and RDF lexical format" do
      assert {:ok, %{amount: dec, currency: "USD"}} = CurrencyAmount.cast_input("5000000.00 USD", [])
      assert Decimal.equal?(dec, Decimal.new("5000000.00"))

      assert {:ok, %{amount: dec2, currency: "EUR"}} = CurrencyAmount.cast_input(%{amount: 1500, currency: "eur"}, [])
      assert Decimal.equal?(dec2, Decimal.new("1500"))

      assert CurrencyAmount.to_rdf_lexical(%{amount: Decimal.new("1500.50"), currency: "USD"}) == "1500.50 USD"
      assert CurrencyAmount.xsd_datatype() == "https://schema.org/MonetaryAmount"
    end

    test "IPAddressRange type validates CIDR format and provides RDF mapping" do
      assert {:ok, "10.100.0.0/16"} = IPAddressRange.cast_input("10.100.0.0/16", [])
      assert {:ok, "192.168.1.1/32"} = IPAddressRange.cast_input("192.168.1.1/32", [])
      assert {:error, _} = IPAddressRange.cast_input("999.999.999.999/99", [])

      assert IPAddressRange.to_rdf_lexical("10.100.0.0/16") == "10.100.0.0/16"
      assert IPAddressRange.xsd_datatype() == "http://www.w3.org/2001/XMLSchema#string"
    end

    test "CriticalityEnum enforces admitted enterprise tiers" do
      assert {:ok, :mission_critical} = CriticalityEnum.cast_input(:mission_critical, [])
      assert {:ok, :high} = CriticalityEnum.cast_input("high", [])
      assert {:error, _} = CriticalityEnum.cast_input("non_existent_tier", [])
      assert :mission_critical in CriticalityEnum.values()
    end
  end

  describe "2. Fortune 5 Ash Resource Factory & Semantic Mappings" do
    test "builds and seeds comprehensive Fortune 5 enterprise dataset in ETS" do
      seed = AshFactory.build_system_seed()

      assert %CloudRegion{code: "us-east-1"} = seed.region
      assert %Cluster{name: "k8s-prod-alpha"} = seed.cluster
      assert [%ServiceInstance{name: "billing-api"} | _] = seed.services
      assert %PaymentGateway{status: :active} = seed.gateway
      assert %LedgerAccount{account_number: "ACCT-9876543210"} = seed.account
      assert %DeploymentPlan{strategy: :blue_green} = seed.plan
      assert %DeploymentPlanService{traffic_weight: 100} = seed.plan_service
      assert %IncidentTicket{ticket_number: "INC-99014"} = seed.incident
      assert %CredentialGrant{grantee_id: "sec-ops-bot-01"} = seed.grant
    end

    test "compiles normalized AshR2RML bundle and renders standards-valid R2RML Turtle" do
      assert {:ok, bundle} = AshFactory.compile_fortune5_bundle()
      assert length(bundle.resources) == 9

      assert {:ok, ttl} = AshFactory.render_fortune5_r2rml()
      assert ttl =~ "https://schema.org/ComputeCluster"
      assert ttl =~ "https://schema.org/SoftwareApplication"
      assert ttl =~ "https://schema.org/FinancialService"
      assert ttl =~ "https://schema.org/BankAccount"
      assert ttl =~ "https://schema.org/Plan"
      assert ttl =~ "https://schema.org/Ticket"
      assert ttl =~ "http://www.w3.org/ns/odrl/2/Permission"
      assert ttl =~ "https://w3id.org/fortune5/ontology#apiKeySecret"
      assert ttl =~ "https://w3id.org/fortune5/ontology#confidentialOpsLog"
    end

    test "calculates service instance SLA uptime percentage" do
      seed = AshFactory.build_system_seed()
      [service1 | _] = seed.services

      {:ok, loaded} = Ash.load(service1, [:sla_label])
      assert loaded.sla_label =~ "99.999%"
    end
  end

  describe "3. ODRL Policy Correspondence and Field Authorization" do
    test "PaymentGateway secret_key is authorized for admin but hidden from viewer" do
      assert Policy.authorized_field?(PaymentGateway, :secret_key, @admin_actor) == true
      assert Policy.authorized_field?(PaymentGateway, :secret_key, @viewer_actor) == false

      mapping = AshR2RML.Resource.Info.mapping!(PaymentGateway)
      filtered_viewer = Policy.filter_for_actor(mapping, @viewer_actor, action: :read)
      filtered_admin = Policy.filter_for_actor(mapping, @admin_actor, action: :read)

      refute :secret_key in Enum.map(filtered_viewer.predicate_object_maps, & &1.attribute)
      assert :secret_key in Enum.map(filtered_admin.predicate_object_maps, & &1.attribute)
    end

    test "IncidentTicket confidential_notes is authorized for security officer and admin" do
      assert Policy.authorized_field?(IncidentTicket, :confidential_notes, @admin_actor) == true
      assert Policy.authorized_field?(IncidentTicket, :confidential_notes, @security_actor) == true
      assert Policy.authorized_field?(IncidentTicket, :confidential_notes, @viewer_actor) == false
    end

    test "LedgerAccount risk_score is authorized for compliance auditor and admin" do
      assert Policy.authorized_field?(LedgerAccount, :risk_score, @admin_actor) == true
      assert Policy.authorized_field?(LedgerAccount, :risk_score, @compliance_actor) == true
      assert Policy.authorized_field?(LedgerAccount, :risk_score, @viewer_actor) == false
    end

    test "CredentialGrant token_hash is strictly authorized for admin" do
      assert Policy.authorized_field?(CredentialGrant, :token_hash, @admin_actor) == true
      assert Policy.authorized_field?(CredentialGrant, :token_hash, @security_actor) == false
      assert Policy.authorized_field?(CredentialGrant, :token_hash, @viewer_actor) == false
    end
  end

  describe "4. BlueGreenDeploymentReactor Saga & Compensations" do
    test "executes full 4-step blue-green deployment saga successfully" do
      inputs = %{
        plan_id: "plan-101",
        cluster_id: "cluster-us-east-1",
        service_id: "billing-service-v2"
      }

      assert {:ok, result} = SagaOrchestrator.run_blue_green(inputs)
      assert result.dns_status == :active_green
      assert result.routed_traffic_percent == 100

      events = SagaOrchestrator.events()
      assert {:run, :drain_traffic, _} = Enum.find(events, &match?({:run, :drain_traffic, _}, &1))
      assert {:run, :provision_green_nodes, _} = Enum.find(events, &match?({:run, :provision_green_nodes, _}, &1))
      assert {:run, :verify_health, _} = Enum.find(events, &match?({:run, :verify_health, _}, &1))
      assert {:run, :switch_dns_routing, _} = Enum.find(events, &match?({:run, :switch_dns_routing, _}, &1))
    end

    test "fault injection on verify_health triggers compensate and undos previous steps" do
      inputs = %{
        plan_id: "plan-fail-01",
        cluster_id: "cluster-01",
        service_id: "billing-service-v2",
        inject_fault_at: :verify_health
      }

      assert {:error, _error} = SagaOrchestrator.run_blue_green(inputs)
      events = SagaOrchestrator.events()

      # 1. Forward run reached verify_health
      assert Enum.any?(events, &match?({:run, :drain_traffic, _}, &1))
      assert Enum.any?(events, &match?({:run, :provision_green_nodes, _}, &1))
      assert Enum.any?(events, &match?({:run, :verify_health, _}, &1))

      # 2. switch_dns_routing was NEVER run
      refute Enum.any?(events, &match?({:run, :switch_dns_routing, _}, &1))

      # 3. Failing step executed compensate
      assert Enum.any?(events, &match?({:compensate, :verify_health, _, _}, &1))

      # 4. Completed preceding steps executed undo
      assert Enum.any?(events, &match?({:undo, :provision_green_nodes, _, _}, &1))
      assert Enum.any?(events, &match?({:undo, :drain_traffic, _, _}, &1))
    end
  end

  describe "5. DisasterRecoveryFailoverReactor Saga & Compensations" do
    test "executes full disaster recovery failover saga successfully" do
      inputs = %{
        primary_region_id: "region-east-failure",
        secondary_region_id: "region-west-dr"
      }

      assert {:ok, result} = SagaOrchestrator.run_disaster_recovery(inputs)
      assert result.status == :failover_complete
      assert result.routing_target == "region-west-dr"

      events = SagaOrchestrator.events()
      assert Enum.any?(events, &match?({:run, :isolate_region, _}, &1))
      assert Enum.any?(events, &match?({:run, :promote_secondary_db, _}, &1))
      assert Enum.any?(events, &match?({:run, :verify_replication, _}, &1))
      assert Enum.any?(events, &match?({:run, :failover_dns, _}, &1))
    end

    test "fault injection on promote_secondary_db triggers rollback and unquarantines region" do
      inputs = %{
        primary_region_id: "region-east-failure",
        secondary_region_id: "region-west-dr",
        inject_fault_at: :promote_secondary_db
      }

      assert {:error, _error} = SagaOrchestrator.run_disaster_recovery(inputs)
      events = SagaOrchestrator.events()

      assert Enum.any?(events, &match?({:run, :isolate_region, _}, &1))
      assert Enum.any?(events, &match?({:run, :promote_secondary_db, _}, &1))
      refute Enum.any?(events, &match?({:run, :verify_replication, _}, &1))
      refute Enum.any?(events, &match?({:run, :failover_dns, _}, &1))

      assert Enum.any?(events, &match?({:compensate, :promote_secondary_db, _, _}, &1))
      assert Enum.any?(events, &match?({:undo, :isolate_region, _, _}, &1))
    end
  end

  describe "6. CredentialRotationReactor Saga & Compensations" do
    test "executes full credential rotation saga successfully" do
      inputs = %{
        grant_id: "grant-771",
        gateway_id: "gw-live-01",
        old_key_id: "key_v1_legacy_88192"
      }

      assert {:ok, result} = SagaOrchestrator.run_credential_rotation(inputs)
      assert result.revocation_status == :legacy_keys_revoked
      assert result.revoked_key_id == "key_v1_legacy_88192"

      events = SagaOrchestrator.events()
      assert Enum.any?(events, &match?({:run, :generate_new_key, _}, &1))
      assert Enum.any?(events, &match?({:run, :rollout_dual_auth, _}, &1))
      assert Enum.any?(events, &match?({:run, :validate_credentials, _}, &1))
      assert Enum.any?(events, &match?({:run, :revoke_old_keys, _}, &1))
    end

    test "fault injection on validate_credentials reverts dual-auth and destroys newly generated key" do
      inputs = %{
        grant_id: "grant-771",
        gateway_id: "gw-live-01",
        old_key_id: "key_v1_legacy_88192",
        inject_fault_at: :validate_credentials
      }

      assert {:error, _error} = SagaOrchestrator.run_credential_rotation(inputs)
      events = SagaOrchestrator.events()

      assert Enum.any?(events, &match?({:run, :generate_new_key, _}, &1))
      assert Enum.any?(events, &match?({:run, :rollout_dual_auth, _}, &1))
      assert Enum.any?(events, &match?({:run, :validate_credentials, _}, &1))
      refute Enum.any?(events, &match?({:run, :revoke_old_keys, _}, &1))

      assert Enum.any?(events, &match?({:compensate, :validate_credentials, _, _}, &1))
      assert Enum.any?(events, &match?({:undo, :rollout_dual_auth, _, _}, &1))
      assert Enum.any?(events, &match?({:undo, :generate_new_key, _, _}, &1))
    end
  end
end
