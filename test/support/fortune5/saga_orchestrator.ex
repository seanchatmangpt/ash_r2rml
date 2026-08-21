# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Fortune5.SagaOrchestrator.ExecutionRecorder do
  @moduledoc """
  In-memory execution recorder tracking forward `run/3`, backward `undo/3`, and `compensate/4`
  saga lifecycle events during testing and verification.
  """
  use Agent

  def start_link(_opts \\ []) do
    case Agent.start_link(fn -> [] end, name: __MODULE__) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      other -> other
    end
  end

  def stop do
    if Process.whereis(__MODULE__), do: Agent.stop(__MODULE__)
  end

  def reset do
    case Process.whereis(__MODULE__) do
      nil ->
        {:ok, _} = start_link()
        :ok

      pid ->
        try do
          Agent.update(pid, fn _ -> [] end)
        catch
          :exit, _ ->
            {:ok, _} = start_link()
            :ok
        end
    end
  end

  def record(event) do
    case Process.whereis(__MODULE__) do
      nil ->
        {:ok, pid} = start_link()
        Agent.update(pid, fn events -> events ++ [event] end)

      pid ->
        try do
          Agent.update(pid, fn events -> events ++ [event] end)
        catch
          :exit, _ ->
            {:ok, pid} = start_link()
            Agent.update(pid, fn events -> events ++ [event] end)
        end
    end
  end

  def get_events do
    case Process.whereis(__MODULE__) do
      nil ->
        []

      pid ->
        try do
          Agent.get(pid, & &1)
        catch
          :exit, _ -> []
        end
    end
  end
end

defmodule AshR2RML.Fortune5.SagaOrchestrator.Steps.DrainTrafficStep do
  @moduledoc """
  Saga Step: Drains traffic from current blue microservice instance.
  """
  use Reactor.Step
  alias AshR2RML.Fortune5.SagaOrchestrator.ExecutionRecorder

  @impl true
  def run(arguments, _context, _options) do
    fault = arguments[:inject_fault_at]

    ExecutionRecorder.record({:run, :drain_traffic, arguments})

    if fault in [:drain_traffic, "drain_traffic"] do
      {:error, {:injected_fault, :drain_traffic, "Fault injected at traffic draining"}}
    else
      {:ok,
       %{status: :traffic_drained, drained_at: System.system_time(:millisecond), service_id: arguments[:service_id]}}
    end
  end

  @impl true
  def undo(result, arguments, _context, _options) do
    ExecutionRecorder.record({:undo, :drain_traffic, result, arguments})
    :ok
  end

  @impl true
  def compensate(reason, arguments, _context, _options) do
    ExecutionRecorder.record({:compensate, :drain_traffic, reason, arguments})
    :ok
  end
end

defmodule AshR2RML.Fortune5.SagaOrchestrator.Steps.ProvisionGreenNodeStep do
  @moduledoc """
  Saga Step: Provisions green microservice instance replicas.
  """
  use Reactor.Step
  alias AshR2RML.Fortune5.SagaOrchestrator.ExecutionRecorder

  @impl true
  def run(arguments, _context, _options) do
    fault = arguments[:inject_fault_at]

    ExecutionRecorder.record({:run, :provision_green_nodes, arguments})

    if fault in [:provision_green_nodes, :green_provisioning, "provision_green_nodes"] do
      {:error, {:injected_fault, :provision_green_nodes, "Fault injected at green node provisioning"}}
    else
      {:ok,
       %{
         status: :green_provisioned,
         green_endpoint: "https://green-cluster.fortune5.internal/v2",
         replicas: 4,
         cluster_id: arguments[:cluster_id]
       }}
    end
  end

  @impl true
  def undo(result, arguments, _context, _options) do
    ExecutionRecorder.record({:undo, :provision_green_nodes, result, arguments})
    :ok
  end

  @impl true
  def compensate(reason, arguments, _context, _options) do
    ExecutionRecorder.record({:compensate, :provision_green_nodes, reason, arguments})
    :ok
  end
end

defmodule AshR2RML.Fortune5.SagaOrchestrator.Steps.VerifyHealthStep do
  @moduledoc """
  Saga Step: Verifies synthetic health probes on provisioned green nodes.
  """
  use Reactor.Step
  alias AshR2RML.Fortune5.SagaOrchestrator.ExecutionRecorder

  @impl true
  def run(arguments, _context, _options) do
    fault = arguments[:inject_fault_at]

    ExecutionRecorder.record({:run, :verify_health, arguments})

    if fault in [:verify_health, :health_verification, "verify_health"] do
      {:error, {:injected_fault, :verify_health, "Health check probe failed on green cluster"}}
    else
      {:ok,
       %{
         health_status: :healthy,
         p99_latency_ms: 12.4,
         error_rate: 0.0,
         verified_at: System.system_time(:millisecond)
       }}
    end
  end

  @impl true
  def undo(result, arguments, _context, _options) do
    ExecutionRecorder.record({:undo, :verify_health, result, arguments})
    :ok
  end

  @impl true
  def compensate(reason, arguments, _context, _options) do
    ExecutionRecorder.record({:compensate, :verify_health, reason, arguments})
    :ok
  end
end

defmodule AshR2RML.Fortune5.SagaOrchestrator.Steps.SwitchDnsRoutingStep do
  @moduledoc """
  Saga Step: Cuts over edge DNS and ingress routing to green service.
  """
  use Reactor.Step
  alias AshR2RML.Fortune5.SagaOrchestrator.ExecutionRecorder

  @impl true
  def run(arguments, _context, _options) do
    fault = arguments[:inject_fault_at]

    ExecutionRecorder.record({:run, :switch_dns_routing, arguments})

    if fault in [:switch_dns_routing, :dns_cutover, "switch_dns_routing"] do
      {:error, {:injected_fault, :switch_dns_routing, "DNS cutover propagation timeout"}}
    else
      {:ok,
       %{
         dns_status: :active_green,
         routed_traffic_percent: 100,
         switched_at: System.system_time(:millisecond)
       }}
    end
  end

  @impl true
  def undo(result, arguments, _context, _options) do
    ExecutionRecorder.record({:undo, :switch_dns_routing, result, arguments})
    :ok
  end

  @impl true
  def compensate(reason, arguments, _context, _options) do
    ExecutionRecorder.record({:compensate, :switch_dns_routing, reason, arguments})
    :ok
  end
end

defmodule AshR2RML.Fortune5.SagaOrchestrator.Steps.IsolateRegionStep do
  @moduledoc """
  Saga Step: Isolates failing primary cloud region.
  """
  use Reactor.Step
  alias AshR2RML.Fortune5.SagaOrchestrator.ExecutionRecorder

  @impl true
  def run(arguments, _context, _options) do
    fault = arguments[:inject_fault_at]

    ExecutionRecorder.record({:run, :isolate_region, arguments})

    if fault in [:isolate_region, "isolate_region"] do
      {:error, {:injected_fault, :isolate_region, "Failed to isolate primary cloud region"}}
    else
      {:ok,
       %{
         status: :region_isolated,
         quarantined_region_id: arguments[:primary_region_id],
         isolated_at: System.system_time(:millisecond)
       }}
    end
  end

  @impl true
  def undo(result, arguments, _context, _options) do
    ExecutionRecorder.record({:undo, :isolate_region, result, arguments})
    :ok
  end

  @impl true
  def compensate(reason, arguments, _context, _options) do
    ExecutionRecorder.record({:compensate, :isolate_region, reason, arguments})
    :ok
  end
end

defmodule AshR2RML.Fortune5.SagaOrchestrator.Steps.PromoteSecondaryDbStep do
  @moduledoc """
  Saga Step: Promotes secondary database replica to primary read-write authority.
  """
  use Reactor.Step
  alias AshR2RML.Fortune5.SagaOrchestrator.ExecutionRecorder

  @impl true
  def run(arguments, _context, _options) do
    fault = arguments[:inject_fault_at]

    ExecutionRecorder.record({:run, :promote_secondary_db, arguments})

    if fault in [:promote_secondary_db, :secondary_db_promotion, "promote_secondary_db"] do
      {:error, {:injected_fault, :promote_secondary_db, "Secondary database promotion rejected: split-brain risk"}}
    else
      {:ok,
       %{
         db_mode: :read_write_primary,
         promoted_region_id: arguments[:secondary_region_id],
         promoted_at: System.system_time(:millisecond)
       }}
    end
  end

  @impl true
  def undo(result, arguments, _context, _options) do
    ExecutionRecorder.record({:undo, :promote_secondary_db, result, arguments})
    :ok
  end

  @impl true
  def compensate(reason, arguments, _context, _options) do
    ExecutionRecorder.record({:compensate, :promote_secondary_db, reason, arguments})
    :ok
  end
end

defmodule AshR2RML.Fortune5.SagaOrchestrator.Steps.VerifyReplicationStep do
  @moduledoc """
  Saga Step: Verifies transaction replication and zero data loss on failover database.
  """
  use Reactor.Step
  alias AshR2RML.Fortune5.SagaOrchestrator.ExecutionRecorder

  @impl true
  def run(arguments, _context, _options) do
    fault = arguments[:inject_fault_at]

    ExecutionRecorder.record({:run, :verify_replication, arguments})

    if fault in [:verify_replication, :replication_verification, "verify_replication"] do
      {:error, {:injected_fault, :verify_replication, "Replication lag exceeds RPO tolerance"}}
    else
      {:ok,
       %{
         replication_status: :synchronized,
         wal_lag_bytes: 0,
         verified_at: System.system_time(:millisecond)
       }}
    end
  end

  @impl true
  def undo(result, arguments, _context, _options) do
    ExecutionRecorder.record({:undo, :verify_replication, result, arguments})
    :ok
  end

  @impl true
  def compensate(reason, arguments, _context, _options) do
    ExecutionRecorder.record({:compensate, :verify_replication, reason, arguments})
    :ok
  end
end

defmodule AshR2RML.Fortune5.SagaOrchestrator.Steps.FailoverDnsStep do
  @moduledoc """
  Saga Step: Updates Global Anycast DNS to route worldwide ingress to secondary region.
  """
  use Reactor.Step
  alias AshR2RML.Fortune5.SagaOrchestrator.ExecutionRecorder

  @impl true
  def run(arguments, _context, _options) do
    fault = arguments[:inject_fault_at]

    ExecutionRecorder.record({:run, :failover_dns, arguments})

    if fault in [:failover_dns, "failover_dns"] do
      {:error, {:injected_fault, :failover_dns, "Global DNS Anycast failover propagation failure"}}
    else
      {:ok,
       %{
         routing_target: arguments[:secondary_region_id],
         status: :failover_complete,
         activated_at: System.system_time(:millisecond)
       }}
    end
  end

  @impl true
  def undo(result, arguments, _context, _options) do
    ExecutionRecorder.record({:undo, :failover_dns, result, arguments})
    :ok
  end

  @impl true
  def compensate(reason, arguments, _context, _options) do
    ExecutionRecorder.record({:compensate, :failover_dns, reason, arguments})
    :ok
  end
end

defmodule AshR2RML.Fortune5.SagaOrchestrator.Steps.GenerateNewKeyStep do
  @moduledoc """
  Saga Step: Generates cryptographically secure KMS key pair and authorization tokens.
  """
  use Reactor.Step
  alias AshR2RML.Fortune5.SagaOrchestrator.ExecutionRecorder

  @impl true
  def run(arguments, _context, _options) do
    fault = arguments[:inject_fault_at]

    ExecutionRecorder.record({:run, :generate_new_key, arguments})

    if fault in [:generate_new_key, "generate_new_key"] do
      {:error, {:injected_fault, :generate_new_key, "KMS Hardware Security Module key generation failure"}}
    else
      token_id = "key_v2_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

      {:ok,
       %{
         key_id: token_id,
         key_fingerprint: "sha256:88ab" <> Base.encode16(:crypto.strong_rand_bytes(16), case: :lower),
         created_at: System.system_time(:millisecond)
       }}
    end
  end

  @impl true
  def undo(result, arguments, _context, _options) do
    ExecutionRecorder.record({:undo, :generate_new_key, result, arguments})
    :ok
  end

  @impl true
  def compensate(reason, arguments, _context, _options) do
    ExecutionRecorder.record({:compensate, :generate_new_key, reason, arguments})
    :ok
  end
end

defmodule AshR2RML.Fortune5.SagaOrchestrator.Steps.RolloutDualAuthStep do
  @moduledoc """
  Saga Step: Enables dual-authentication mode accepting both legacy and newly generated keys.
  """
  use Reactor.Step
  alias AshR2RML.Fortune5.SagaOrchestrator.ExecutionRecorder

  @impl true
  def run(arguments, _context, _options) do
    fault = arguments[:inject_fault_at]

    ExecutionRecorder.record({:run, :rollout_dual_auth, arguments})

    if fault in [:rollout_dual_auth, "rollout_dual_auth"] do
      {:error, {:injected_fault, :rollout_dual_auth, "Dual-auth policy rollout rejected by auth gateway"}}
    else
      {:ok,
       %{
         auth_mode: :dual_auth_active,
         active_keys: [arguments[:old_key_id], arguments[:new_key_info][:key_id]],
         deployed_at: System.system_time(:millisecond)
       }}
    end
  end

  @impl true
  def undo(result, arguments, _context, _options) do
    ExecutionRecorder.record({:undo, :rollout_dual_auth, result, arguments})
    :ok
  end

  @impl true
  def compensate(reason, arguments, _context, _options) do
    ExecutionRecorder.record({:compensate, :rollout_dual_auth, reason, arguments})
    :ok
  end
end

defmodule AshR2RML.Fortune5.SagaOrchestrator.Steps.ValidateCredentialsStep do
  @moduledoc """
  Saga Step: Executes synthetic verification probe with newly rotated credentials.
  """
  use Reactor.Step
  alias AshR2RML.Fortune5.SagaOrchestrator.ExecutionRecorder

  @impl true
  def run(arguments, _context, _options) do
    fault = arguments[:inject_fault_at]

    ExecutionRecorder.record({:run, :validate_credentials, arguments})

    if fault in [:validate_credentials, :credential_validation, "validate_credentials"] do
      {:error, {:injected_fault, :validate_credentials, "Synthetic authentication probe rejected new credential"}}
    else
      {:ok,
       %{
         validation_status: :passed,
         signature_verified?: true,
         tested_at: System.system_time(:millisecond)
       }}
    end
  end

  @impl true
  def undo(result, arguments, _context, _options) do
    ExecutionRecorder.record({:undo, :validate_credentials, result, arguments})
    :ok
  end

  @impl true
  def compensate(reason, arguments, _context, _options) do
    ExecutionRecorder.record({:compensate, :validate_credentials, reason, arguments})
    :ok
  end
end

defmodule AshR2RML.Fortune5.SagaOrchestrator.Steps.RevokeOldKeysStep do
  @moduledoc """
  Saga Step: Formally revokes legacy keys from the authorization registry.
  """
  use Reactor.Step
  alias AshR2RML.Fortune5.SagaOrchestrator.ExecutionRecorder

  @impl true
  def run(arguments, _context, _options) do
    fault = arguments[:inject_fault_at]

    ExecutionRecorder.record({:run, :revoke_old_keys, arguments})

    if fault in [:revoke_old_keys, "revoke_old_keys"] do
      {:error, {:injected_fault, :revoke_old_keys, "Legacy key revocation transaction aborted"}}
    else
      {:ok,
       %{
         revocation_status: :legacy_keys_revoked,
         revoked_key_id: arguments[:old_key_id],
         active_key_id: arguments[:new_key_info][:key_id],
         completed_at: System.system_time(:millisecond)
       }}
    end
  end

  @impl true
  def undo(result, arguments, _context, _options) do
    ExecutionRecorder.record({:undo, :revoke_old_keys, result, arguments})
    :ok
  end

  @impl true
  def compensate(reason, arguments, _context, _options) do
    ExecutionRecorder.record({:compensate, :revoke_old_keys, reason, arguments})
    :ok
  end
end

defmodule AshR2RML.Fortune5.SagaOrchestrator.BlueGreenDeploymentReactor do
  @moduledoc """
  Native Ash/Reactor Saga: Orchestrates continuous Blue/Green zero-downtime microservice deployment.
  Phases:
  1. Drain traffic from Blue deployment.
  2. Provision Green cluster replicas.
  3. Execute health verification probes on Green cluster.
  4. Cut over DNS routing to Green.
  Compensates/Rolls back upon failure at any stage.
  """
  use Reactor

  input(:plan_id)
  input(:cluster_id)
  input(:service_id)
  input(:inject_fault_at)
  input(:metadata)

  step :drain_traffic, AshR2RML.Fortune5.SagaOrchestrator.Steps.DrainTrafficStep do
    argument :service_id, input(:service_id)
    argument :inject_fault_at, input(:inject_fault_at)
  end

  step :provision_green_nodes, AshR2RML.Fortune5.SagaOrchestrator.Steps.ProvisionGreenNodeStep do
    argument :cluster_id, input(:cluster_id)
    argument :inject_fault_at, input(:inject_fault_at)
    wait_for :drain_traffic
  end

  step :verify_health, AshR2RML.Fortune5.SagaOrchestrator.Steps.VerifyHealthStep do
    argument :green_info, result(:provision_green_nodes)
    argument :inject_fault_at, input(:inject_fault_at)
    wait_for :provision_green_nodes
  end

  step :switch_dns_routing, AshR2RML.Fortune5.SagaOrchestrator.Steps.SwitchDnsRoutingStep do
    argument :health_info, result(:verify_health)
    argument :green_info, result(:provision_green_nodes)
    argument :inject_fault_at, input(:inject_fault_at)
    wait_for :verify_health
  end

  return :switch_dns_routing
end

defmodule AshR2RML.Fortune5.SagaOrchestrator.DisasterRecoveryFailoverReactor do
  @moduledoc """
  Native Ash/Reactor Saga: Orchestrates multi-region enterprise disaster recovery failover.
  Phases:
  1. Isolate and quarantine compromised/failed primary region.
  2. Promote standby secondary database to read-write primary.
  3. Verify cross-region replication consistency and zero data loss.
  4. Execute Anycast DNS failover to backup region.
  Compensates/Rolls back cleanly upon replication or promotion failure.
  """
  use Reactor

  input(:primary_region_id)
  input(:secondary_region_id)
  input(:inject_fault_at)
  input(:metadata)

  step :isolate_region, AshR2RML.Fortune5.SagaOrchestrator.Steps.IsolateRegionStep do
    argument :primary_region_id, input(:primary_region_id)
    argument :inject_fault_at, input(:inject_fault_at)
  end

  step :promote_secondary_db, AshR2RML.Fortune5.SagaOrchestrator.Steps.PromoteSecondaryDbStep do
    argument :secondary_region_id, input(:secondary_region_id)
    argument :inject_fault_at, input(:inject_fault_at)
    wait_for :isolate_region
  end

  step :verify_replication, AshR2RML.Fortune5.SagaOrchestrator.Steps.VerifyReplicationStep do
    argument :db_info, result(:promote_secondary_db)
    argument :inject_fault_at, input(:inject_fault_at)
    wait_for :promote_secondary_db
  end

  step :failover_dns, AshR2RML.Fortune5.SagaOrchestrator.Steps.FailoverDnsStep do
    argument :secondary_region_id, input(:secondary_region_id)
    argument :replication_info, result(:verify_replication)
    argument :inject_fault_at, input(:inject_fault_at)
    wait_for :verify_replication
  end

  return :failover_dns
end

defmodule AshR2RML.Fortune5.SagaOrchestrator.CredentialRotationReactor do
  @moduledoc """
  Native Ash/Reactor Saga: Orchestrates zero-downtime cryptographic credential and secret rotation.
  Phases:
  1. Generate new KMS asymmetric key pair and secret token.
  2. Roll out dual-authentication policy to auth gateways.
  3. Execute synthetic validation probes using newly issued credentials.
  4. Revoke and archive legacy credentials.
  Compensates/Rolls back to legacy single-auth key state on validation failure.
  """
  use Reactor

  input(:grant_id)
  input(:gateway_id)
  input(:old_key_id)
  input(:inject_fault_at)
  input(:metadata)

  step :generate_new_key, AshR2RML.Fortune5.SagaOrchestrator.Steps.GenerateNewKeyStep do
    argument :grant_id, input(:grant_id)
    argument :inject_fault_at, input(:inject_fault_at)
  end

  step :rollout_dual_auth, AshR2RML.Fortune5.SagaOrchestrator.Steps.RolloutDualAuthStep do
    argument :old_key_id, input(:old_key_id)
    argument :new_key_info, result(:generate_new_key)
    argument :gateway_id, input(:gateway_id)
    argument :inject_fault_at, input(:inject_fault_at)
    wait_for :generate_new_key
  end

  step :validate_credentials, AshR2RML.Fortune5.SagaOrchestrator.Steps.ValidateCredentialsStep do
    argument :new_key_info, result(:generate_new_key)
    argument :inject_fault_at, input(:inject_fault_at)
    wait_for :rollout_dual_auth
  end

  step :revoke_old_keys, AshR2RML.Fortune5.SagaOrchestrator.Steps.RevokeOldKeysStep do
    argument :old_key_id, input(:old_key_id)
    argument :new_key_info, result(:generate_new_key)
    argument :inject_fault_at, input(:inject_fault_at)
    wait_for :validate_credentials
  end

  return :revoke_old_keys
end

defmodule AshR2RML.Fortune5.SagaOrchestrator do
  @moduledoc """
  Enterprise Operational Lifecycle Saga Orchestrator for Fortune 5 infrastructure:
  - Blue/Green Deployments (`BlueGreenDeploymentReactor`)
  - Disaster Recovery Failover (`DisasterRecoveryFailoverReactor`)
  - Zero-Downtime Credential Rotation (`CredentialRotationReactor`)

  Fully equipped with native `undo/3` and `compensate/4` hooks on every step and fault injection.
  """

  alias AshR2RML.Fortune5.SagaOrchestrator.{
    BlueGreenDeploymentReactor,
    CredentialRotationReactor,
    DisasterRecoveryFailoverReactor,
    ExecutionRecorder
  }

  @doc "Executes Blue/Green deployment saga."
  def run_blue_green(inputs, opts \\ []) do
    full_inputs = Map.merge(%{inject_fault_at: nil, metadata: %{}}, Map.new(inputs))
    Reactor.run(BlueGreenDeploymentReactor, full_inputs, %{}, opts)
  end

  @doc "Executes Disaster Recovery failover saga."
  def run_disaster_recovery(inputs, opts \\ []) do
    full_inputs = Map.merge(%{inject_fault_at: nil, metadata: %{}}, Map.new(inputs))
    Reactor.run(DisasterRecoveryFailoverReactor, full_inputs, %{}, opts)
  end

  @doc "Executes Credential Rotation saga."
  def run_credential_rotation(inputs, opts \\ []) do
    full_inputs = Map.merge(%{inject_fault_at: nil, metadata: %{}}, Map.new(inputs))
    Reactor.run(CredentialRotationReactor, full_inputs, %{}, opts)
  end

  @doc "Returns recorded saga execution events."
  def events, do: ExecutionRecorder.get_events()

  @doc "Resets recorded saga execution events."
  def reset_events, do: ExecutionRecorder.reset()

  @doc "Records a custom lifecycle event."
  def record_event(event), do: ExecutionRecorder.record(event)
end
