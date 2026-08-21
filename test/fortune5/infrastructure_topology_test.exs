# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Fortune5.InfrastructureTopologyTest do
  @moduledoc """
  Fortune 5 Global Infrastructure Topology & Multi-Hop Reference Closure Test Suite.

  Exercises:
  1. Multi-tier infrastructure topology hierarchy:
     CloudRegion -> ComputeCluster -> HostNode -> DatabaseInstance -> DatabaseReplica
  2. Multi-hop reference object maps and parent triples maps across 5 distinct topological tiers.
  3. Dependency-closed bundle expansion when compiling leaf or root resources.
  4. R2RML standards compliance: child/parent join conditions, subject templates, and RDF classes.
  5. ETS data-layer multi-tier graph persistence and traversal.
  """
  use ExUnit.Case, async: true
  require Ash.Query

  alias AshR2RML.Mapping
  alias AshR2RML.Mapping.{Bundle, JoinCondition}

  # --- Domain & Resources Definition ---

  defmodule TopologyDomain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.Fortune5.InfrastructureTopologyTest.CloudRegion
      resource AshR2RML.Fortune5.InfrastructureTopologyTest.ComputeCluster
      resource AshR2RML.Fortune5.InfrastructureTopologyTest.HostNode
      resource AshR2RML.Fortune5.InfrastructureTopologyTest.DatabaseInstance
      resource AshR2RML.Fortune5.InfrastructureTopologyTest.DatabaseReplica
    end
  end

  # Tier 1: Cloud Region
  defmodule CloudRegion do
    use Ash.Resource,
      domain: AshR2RML.Fortune5.InfrastructureTopologyTest.TopologyDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :region_code, :string, allow_nil?: false, public?: true
      attribute :datacenter_location, :string, allow_nil?: false, public?: true
      attribute :active, :boolean, allow_nil?: false, default: true, public?: true
    end

    identities do
      identity :region_code_unique, [:region_code],
        pre_check_with: AshR2RML.Fortune5.InfrastructureTopologyTest.TopologyDomain
    end

    relationships do
      has_many :clusters, AshR2RML.Fortune5.InfrastructureTopologyTest.ComputeCluster do
        source_attribute :id
        destination_attribute :region_id
        public? true
      end
    end

    actions do
      default_accept :*
      defaults [:read, :create, :update, :destroy]
    end

    r2rml do
      table_name("infra_cloud_regions")
      class("https://infra.fortune5.com/ontology/CloudRegion")

      subject do
        template("https://infra.fortune5.com/regions/{region_code}")
      end

      property(:region_code, "https://infra.fortune5.com/ontology/regionCode")
      property(:datacenter_location, "https://infra.fortune5.com/ontology/datacenterLocation")
      property(:active, "https://infra.fortune5.com/ontology/isActive")
    end
  end

  # Tier 2: Compute Cluster
  defmodule ComputeCluster do
    use Ash.Resource,
      domain: AshR2RML.Fortune5.InfrastructureTopologyTest.TopologyDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :cluster_name, :string, allow_nil?: false, public?: true
      attribute :orchestrator_type, :string, allow_nil?: false, default: "kubernetes", public?: true
      attribute :region_id, :uuid, allow_nil?: false, public?: true
    end

    relationships do
      belongs_to :region, AshR2RML.Fortune5.InfrastructureTopologyTest.CloudRegion do
        source_attribute :region_id
        destination_attribute :id
        allow_nil? false
        public? true
      end

      has_many :nodes, AshR2RML.Fortune5.InfrastructureTopologyTest.HostNode do
        source_attribute :id
        destination_attribute :cluster_id
        public? true
      end
    end

    actions do
      default_accept :*
      defaults [:read, :create, :update, :destroy]
    end

    r2rml do
      table_name("infra_compute_clusters")
      class("https://infra.fortune5.com/ontology/ComputeCluster")

      subject do
        template("https://infra.fortune5.com/clusters/{id}")
      end

      property(:cluster_name, "https://infra.fortune5.com/ontology/clusterName")
      property(:orchestrator_type, "https://infra.fortune5.com/ontology/orchestratorType")
      reference(:region, "https://infra.fortune5.com/ontology/locatedInRegion")
    end
  end

  # Tier 3: Host Node
  defmodule HostNode do
    use Ash.Resource,
      domain: AshR2RML.Fortune5.InfrastructureTopologyTest.TopologyDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :hostname, :string, allow_nil?: false, public?: true
      attribute :ip_address, :string, allow_nil?: false, public?: true
      attribute :cpu_cores, :integer, allow_nil?: false, default: 64, public?: true
      attribute :memory_gb, :integer, allow_nil?: false, default: 256, public?: true
      attribute :cluster_id, :uuid, allow_nil?: false, public?: true
    end

    identities do
      identity :hostname_unique, [:hostname],
        pre_check_with: AshR2RML.Fortune5.InfrastructureTopologyTest.TopologyDomain
    end

    relationships do
      belongs_to :cluster, AshR2RML.Fortune5.InfrastructureTopologyTest.ComputeCluster do
        source_attribute :cluster_id
        destination_attribute :id
        allow_nil? false
        public? true
      end

      has_many :databases, AshR2RML.Fortune5.InfrastructureTopologyTest.DatabaseInstance do
        source_attribute :id
        destination_attribute :host_id
        public? true
      end
    end

    actions do
      default_accept :*
      defaults [:read, :create, :update, :destroy]
    end

    r2rml do
      table_name("infra_host_nodes")
      class("https://infra.fortune5.com/ontology/HostNode")

      subject do
        template("https://infra.fortune5.com/hosts/{hostname}")
      end

      property(:hostname, "https://infra.fortune5.com/ontology/hostName")
      property(:ip_address, "https://infra.fortune5.com/ontology/ipAddress")
      property(:cpu_cores, "https://infra.fortune5.com/ontology/cpuCores")
      property(:memory_gb, "https://infra.fortune5.com/ontology/memoryGigabytes")
      reference(:cluster, "https://infra.fortune5.com/ontology/memberOfCluster")
    end
  end

  # Tier 4: Database Instance
  defmodule DatabaseInstance do
    use Ash.Resource,
      domain: AshR2RML.Fortune5.InfrastructureTopologyTest.TopologyDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :instance_name, :string, allow_nil?: false, public?: true
      attribute :engine, :string, allow_nil?: false, default: "postgresql", public?: true
      attribute :port, :integer, allow_nil?: false, default: 5432, public?: true
      attribute :host_id, :uuid, allow_nil?: false, public?: true
    end

    relationships do
      belongs_to :host, AshR2RML.Fortune5.InfrastructureTopologyTest.HostNode do
        source_attribute :host_id
        destination_attribute :id
        allow_nil? false
        public? true
      end

      has_many :replicas, AshR2RML.Fortune5.InfrastructureTopologyTest.DatabaseReplica do
        source_attribute :id
        destination_attribute :primary_instance_id
        public? true
      end
    end

    actions do
      default_accept :*
      defaults [:read, :create, :update, :destroy]
    end

    r2rml do
      table_name("infra_database_instances")
      class("https://infra.fortune5.com/ontology/DatabaseInstance")

      subject do
        template("https://infra.fortune5.com/databases/{id}")
      end

      property(:instance_name, "https://infra.fortune5.com/ontology/instanceName")
      property(:engine, "https://infra.fortune5.com/ontology/engine")
      property(:port, "https://infra.fortune5.com/ontology/port")
      reference(:host, "https://infra.fortune5.com/ontology/runsOnHost")
    end
  end

  # Tier 5: Database Replica
  defmodule DatabaseReplica do
    use Ash.Resource,
      domain: AshR2RML.Fortune5.InfrastructureTopologyTest.TopologyDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :replica_identifier, :string, allow_nil?: false, public?: true
      attribute :replica_type, :string, allow_nil?: false, default: "read_replica", public?: true
      attribute :lag_ms, :integer, allow_nil?: false, default: 0, public?: true
      attribute :primary_instance_id, :uuid, allow_nil?: false, public?: true
    end

    relationships do
      belongs_to :primary_instance, AshR2RML.Fortune5.InfrastructureTopologyTest.DatabaseInstance do
        source_attribute :primary_instance_id
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
      table_name("infra_database_replicas")
      class("https://infra.fortune5.com/ontology/DatabaseReplica")

      subject do
        template("https://infra.fortune5.com/replicas/{id}")
      end

      property(:replica_identifier, "https://infra.fortune5.com/ontology/replicaIdentifier")
      property(:replica_type, "https://infra.fortune5.com/ontology/replicaType")
      property(:lag_ms, "https://infra.fortune5.com/ontology/replicationLagMs")
      reference(:primary_instance, "https://infra.fortune5.com/ontology/replicatesPrimary")
    end
  end

  # --- Tests ---

  describe "1. Multi-Tier Infrastructure Topology Data Persistence" do
    test "persists entire 5-tier infrastructure stack and traverses relationships" do
      # 1. Cloud Region
      region =
        CloudRegion
        |> Ash.Changeset.for_create(:create, %{
          region_code: "us-east-1",
          datacenter_location: "Northern Virginia DC-1",
          active: true
        })
        |> Ash.create!()

      # 2. Compute Cluster
      cluster =
        ComputeCluster
        |> Ash.Changeset.for_create(:create, %{
          cluster_name: "prod-core-k8s-01",
          orchestrator_type: "kubernetes-1.30",
          region_id: region.id
        })
        |> Ash.create!()

      # 3. Host Node
      host =
        HostNode
        |> Ash.Changeset.for_create(:create, %{
          hostname: "node-c5-metal-042.fortune5.net",
          ip_address: "10.128.4.42",
          cpu_cores: 128,
          memory_gb: 512,
          cluster_id: cluster.id
        })
        |> Ash.create!()

      # 4. Database Instance
      db =
        DatabaseInstance
        |> Ash.Changeset.for_create(:create, %{
          instance_name: "db-ledger-primary-01",
          engine: "postgresql-16",
          port: 5432,
          host_id: host.id
        })
        |> Ash.create!()

      # 5. Database Replica
      replica =
        DatabaseReplica
        |> Ash.Changeset.for_create(:create, %{
          replica_identifier: "db-ledger-ro-01",
          replica_type: "read_replica",
          lag_ms: 12,
          primary_instance_id: db.id
        })
        |> Ash.create!()

      assert replica.id != nil

      # Multi-hop traversal test from Replica to Region
      loaded_replica =
        DatabaseReplica
        |> Ash.Query.filter(id == ^replica.id)
        |> Ash.Query.load(primary_instance: [host: [cluster: :region]])
        |> Ash.read_one!()

      assert loaded_replica.primary_instance.instance_name == "db-ledger-primary-01"
      assert loaded_replica.primary_instance.host.hostname == "node-c5-metal-042.fortune5.net"
      assert loaded_replica.primary_instance.host.cluster.cluster_name == "prod-core-k8s-01"
      assert loaded_replica.primary_instance.host.cluster.region.region_code == "us-east-1"
    end
  end

  describe "2. Multi-Hop R2RML Reference Object Maps & Bundle Validation" do
    test "compiles individual mapping with reference object map join conditions" do
      assert {:ok, db_mapping} = AshR2RML.Resource.Info.mapping_result(DatabaseInstance)

      assert db_mapping.ash_resource == DatabaseInstance
      assert db_mapping.logical_table.table_name == "infra_database_instances"

      [ref] = db_mapping.reference_object_maps
      assert ref.relationship == :host
      assert ref.predicate_iri == "https://infra.fortune5.com/ontology/runsOnHost"
      assert ref.parent_resource == HostNode
      assert [%JoinCondition{child: "host_id", parent: "id"}] = ref.joins
    end

    test "compiles closed bundle starting from leaf DatabaseReplica, expanding all 5 tiers" do
      assert {:ok, %Bundle{resources: resources} = bundle} = AshR2RML.compile(DatabaseReplica)

      # Proves dependency closure automatically pulled in all 5 upstream dependencies
      resource_modules = Enum.map(resources, & &1.ash_resource)
      assert DatabaseReplica in resource_modules
      assert DatabaseInstance in resource_modules
      assert HostNode in resource_modules
      assert ComputeCluster in resource_modules
      assert CloudRegion in resource_modules

      # Validate entire closed multi-hop bundle
      assert :ok = Mapping.validate(bundle)
    end

    test "renders complete standards-valid R2RML Turtle with multi-hop parent triples maps" do
      assert {:ok, %Bundle{} = bundle} =
               AshR2RML.compile([CloudRegion, ComputeCluster, HostNode, DatabaseInstance, DatabaseReplica])

      assert {:ok, turtle} = AshR2RML.render(bundle)
      assert is_binary(turtle)

      # Verify prefixes
      assert String.contains?(turtle, "@prefix rr: <http://www.w3.org/ns/r2rml#> .")

      # Verify TriplesMap declarations
      assert String.contains?(turtle, "<#AshR2RML_Fortune5_InfrastructureTopologyTest_CloudRegion> a rr:TriplesMap")
      assert String.contains?(turtle, "<#AshR2RML_Fortune5_InfrastructureTopologyTest_ComputeCluster> a rr:TriplesMap")
      assert String.contains?(turtle, "<#AshR2RML_Fortune5_InfrastructureTopologyTest_HostNode> a rr:TriplesMap")

      assert String.contains?(
               turtle,
               "<#AshR2RML_Fortune5_InfrastructureTopologyTest_DatabaseInstance> a rr:TriplesMap"
             )

      assert String.contains?(turtle, "<#AshR2RML_Fortune5_InfrastructureTopologyTest_DatabaseReplica> a rr:TriplesMap")

      # Verify multi-hop parent triples map joins in Turtle
      assert String.contains?(turtle, "rr:parentTriplesMap <#AshR2RML_Fortune5_InfrastructureTopologyTest_CloudRegion>")
      assert String.contains?(turtle, "rr:joinCondition [ rr:child \"region_id\"; rr:parent \"id\" ]")

      assert String.contains?(
               turtle,
               "rr:parentTriplesMap <#AshR2RML_Fortune5_InfrastructureTopologyTest_ComputeCluster>"
             )

      assert String.contains?(turtle, "rr:joinCondition [ rr:child \"cluster_id\"; rr:parent \"id\" ]")

      assert String.contains?(turtle, "rr:parentTriplesMap <#AshR2RML_Fortune5_InfrastructureTopologyTest_HostNode>")
      assert String.contains?(turtle, "rr:joinCondition [ rr:child \"host_id\"; rr:parent \"id\" ]")

      assert String.contains?(
               turtle,
               "rr:parentTriplesMap <#AshR2RML_Fortune5_InfrastructureTopologyTest_DatabaseInstance>"
             )

      assert String.contains?(turtle, "rr:joinCondition [ rr:child \"primary_instance_id\"; rr:parent \"id\" ]")
    end
  end
end
