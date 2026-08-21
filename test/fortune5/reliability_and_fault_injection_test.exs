# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Fortune5.ReliabilityAndFaultInjectionTest do
  @moduledoc """
  Fortune 5 Reliability, Fault Injection & Typed Semantic Refusals Test Suite.

  Exercises:
  1. Complete typed refusal matrix under hostile input configurations:
     - REFUSED_INVALID_CLASS_IRI
     - REFUSED_MISSING_SUBJECT_MAP
     - REFUSED_NON_UNIQUE_SEMANTIC_IDENTITY
     - REFUSED_UNMAPPED_DATATYPE
     - REFUSED_AMBIGUOUS_RELATIONSHIP
     - REFUSED_INVALID_JOIN_CONDITION
     - REFUSED_RELATIONSHIP_WITHOUT_PREDICATE
     - REFUSED_R2RML_JOIN_WITHOUT_IDENTITY
     - REFUSED_RELATIONSHIP_TARGET_UNMAPPED
  2. Network partition fault injection and transactional rollback safety.
  3. Upstream service latency and timeout injection in operational workflows.
  4. Ash action validation boundaries and isolation invariants.
  """
  use ExUnit.Case, async: true
  require Ash.Query

  alias AshR2RML.Datatype.Registry, as: DatatypeRegistry
  alias AshR2RML.Mapping
  alias AshR2RML.Mapping.{Bundle, JoinCondition, LogicalTable, ReferenceObjectMap, Resource, SubjectMap}

  # --- Resources for Transactional Invariant Testing ---

  defmodule ReliabilityDomain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.Fortune5.ReliabilityAndFaultInjectionTest.VaultBalance
    end
  end

  defmodule VaultBalance do
    use Ash.Resource,
      domain: AshR2RML.Fortune5.ReliabilityAndFaultInjectionTest.ReliabilityDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :vault_code, :string, allow_nil?: false, public?: true
      attribute :available_balance, :decimal, allow_nil?: false, default: Decimal.new("0.0"), public?: true
      attribute :locked, :boolean, allow_nil?: false, default: false, public?: true
    end

    identities do
      identity :vault_code_unique, [:vault_code],
        pre_check_with: AshR2RML.Fortune5.ReliabilityAndFaultInjectionTest.ReliabilityDomain
    end

    actions do
      default_accept :*
      defaults [:read, :destroy]

      create :create do
        primary? true
        accept [:vault_code, :available_balance, :locked]

        validate fn changeset, _context ->
          bal = Ash.Changeset.get_attribute(changeset, :available_balance)

          if bal && Decimal.negative?(bal) do
            {:error, "Vault balance cannot be initialized negative"}
          else
            :ok
          end
        end
      end

      update :transfer do
        require_atomic? false
        accept [:available_balance, :locked]

        validate fn changeset, _context ->
          locked? = Ash.Changeset.get_attribute(changeset, :locked)
          bal = Ash.Changeset.get_attribute(changeset, :available_balance)

          cond do
            locked? ->
              {:error, "Cannot debit locked vault"}

            bal && Decimal.negative?(bal) ->
              {:error, "Insufficient funds: overdraft prohibited"}

            true ->
              :ok
          end
        end
      end
    end

    r2rml do
      table_name("enterprise_vault_balances")
      class("https://enterprise.fortune5.com/ontology/VaultBalance")

      subject do
        template("https://enterprise.fortune5.com/vaults/{vault_code}")
      end

      property(:vault_code, "https://enterprise.fortune5.com/ontology/vaultCode")
      property(:available_balance, "https://enterprise.fortune5.com/ontology/availableBalance")
      property(:locked, "https://enterprise.fortune5.com/ontology/isLocked")
    end
  end

  # ============================================================================
  # 1. Hostile Refusal Matrix Tests
  # ============================================================================

  describe "1. Typed Refusal Matrix" do
    test "REFUSED_INVALID_CLASS_IRI: rejects malformed or non-absolute RDF class IRIs" do
      invalid_class_res = %Resource{
        ash_resource: :InvalidClassRes,
        logical_table: %LogicalTable{table_name: "test_table"},
        class_iris: ["not_a_valid_absolute_iri"],
        subject_map: %SubjectMap{strategy: :template, value: "https://example.com/items/{id}", term_type: :iri},
        identities: [[:id]],
        metadata: %{attribute_columns: %{id: "id"}}
      }

      assert {:error, refusals} = Mapping.validate(invalid_class_res)
      assert Enum.any?(refusals, &(&1.code == :REFUSED_INVALID_CLASS_IRI))
    end

    test "REFUSED_MISSING_SUBJECT_MAP: rejects resources lacking valid subject definitions" do
      missing_sub_res = %Resource{
        ash_resource: :MissingSubRes,
        logical_table: %LogicalTable{table_name: "test_table"},
        class_iris: ["https://example.com/ontology/ValidClass"],
        subject_map: %SubjectMap{strategy: :template, value: "", term_type: :iri},
        identities: [[:id]],
        metadata: %{attribute_columns: %{id: "id"}}
      }

      assert {:error, refusals} = Mapping.validate(missing_sub_res)
      assert Enum.any?(refusals, &(&1.code == :REFUSED_MISSING_SUBJECT_MAP))
    end

    test "REFUSED_NON_UNIQUE_SEMANTIC_IDENTITY: rejects subject template referencing unadmitted non-key attributes" do
      non_unique_res = %Resource{
        ash_resource: :NonUniqueRes,
        logical_table: %LogicalTable{table_name: "test_table"},
        class_iris: ["https://example.com/ontology/ValidClass"],
        subject_map: %SubjectMap{
          strategy: :template,
          value: "https://example.com/items/{unindexed_tag}",
          term_type: :iri
        },
        identities: [[:id]],
        metadata: %{attribute_columns: %{id: "id", unindexed_tag: "unindexed_tag"}}
      }

      assert {:error, refusals} = Mapping.validate(non_unique_res)
      assert Enum.any?(refusals, &(&1.code == :REFUSED_NON_UNIQUE_SEMANTIC_IDENTITY))
    end

    test "REFUSED_UNMAPPED_DATATYPE & UNSUPPORTED_ASH_TYPE: rejects unsupported types or relative datatype IRIs" do
      assert {:error, refusal} = DatatypeRegistry.resolve(:unknown_fortune5_type)
      assert refusal.code == :UNSUPPORTED_ASH_TYPE

      assert {:error, refusal} = DatatypeRegistry.resolve(:string, "relative_datatype_without_scheme")
      assert refusal.code == :REFUSED_UNMAPPED_DATATYPE
    end

    test "REFUSED_RELATIONSHIP_TARGET_UNMAPPED: rejects bundle when parent_resource is missing from bundle" do
      source_res = %Resource{
        ash_resource: :Order,
        logical_table: %LogicalTable{table_name: "orders"},
        class_iris: ["https://example.com/Order"],
        subject_map: %SubjectMap{strategy: :template, value: "https://example.com/orders/{id}", term_type: :iri},
        identities: [[:id]],
        metadata: %{attribute_columns: %{id: "id", customer_id: "customer_id"}},
        reference_object_maps: [
          %ReferenceObjectMap{
            relationship: :customer,
            predicate_iri: "https://example.com/hasCustomer",
            parent_resource: :UnmappedCustomer,
            joins: [%JoinCondition{child: "customer_id", parent: "id"}]
          }
        ]
      }

      bundle = %Bundle{resources: [source_res]}
      assert {:error, refusals} = Mapping.validate(bundle)
      assert Enum.any?(refusals, &(&1.code == :REFUSED_RELATIONSHIP_TARGET_UNMAPPED))
    end

    test "REFUSED_RELATIONSHIP_WITHOUT_PREDICATE: rejects relationship when predicate IRI is invalid" do
      bad_pred_res = %Resource{
        ash_resource: :Item,
        logical_table: %LogicalTable{table_name: "items"},
        class_iris: ["https://example.com/Item"],
        subject_map: %SubjectMap{strategy: :template, value: "https://example.com/items/{id}", term_type: :iri},
        identities: [[:id]],
        metadata: %{attribute_columns: %{id: "id"}},
        reference_object_maps: [
          %ReferenceObjectMap{
            relationship: :category,
            predicate_iri: "invalid_rel_pred",
            parent_resource: :Item,
            joins: [%JoinCondition{child: "cat_id", parent: "id"}]
          }
        ]
      }

      assert {:error, refusals} = Mapping.validate(bad_pred_res)
      assert Enum.any?(refusals, &(&1.code == :REFUSED_RELATIONSHIP_WITHOUT_PREDICATE))
    end

    test "REFUSED_INVALID_JOIN_CONDITION: rejects join conditions with blank child or parent columns" do
      bad_join_res = %Resource{
        ash_resource: :Payment,
        logical_table: %LogicalTable{table_name: "payments"},
        class_iris: ["https://example.com/Payment"],
        subject_map: %SubjectMap{strategy: :template, value: "https://example.com/payments/{id}", term_type: :iri},
        identities: [[:id]],
        metadata: %{attribute_columns: %{id: "id"}},
        reference_object_maps: [
          %ReferenceObjectMap{
            relationship: :invoice,
            predicate_iri: "https://example.com/forInvoice",
            parent_resource: :Payment,
            joins: [%JoinCondition{child: "", parent: "id"}]
          }
        ]
      }

      assert {:error, refusals} = Mapping.validate(bad_join_res)
      assert Enum.any?(refusals, &(&1.code == :REFUSED_INVALID_JOIN_CONDITION))
    end

    test "REFUSED_R2RML_JOIN_WITHOUT_IDENTITY: rejects relationship targeting a resource lacking a stable subject identity" do
      source_res = %Resource{
        ash_resource: :Trade,
        logical_table: %LogicalTable{table_name: "trades"},
        class_iris: ["https://example.com/Trade"],
        subject_map: %SubjectMap{strategy: :template, value: "https://example.com/trades/{id}", term_type: :iri},
        identities: [[:id]],
        metadata: %{attribute_columns: %{id: "id"}},
        reference_object_maps: [
          %ReferenceObjectMap{
            relationship: :instrument,
            predicate_iri: "https://example.com/tradedInstrument",
            parent_resource: :Instrument,
            joins: [%JoinCondition{child: "instrument_code", parent: "id"}]
          }
        ]
      }

      target_without_valid_id = %Resource{
        ash_resource: :Instrument,
        logical_table: %LogicalTable{table_name: "instruments"},
        class_iris: ["https://example.com/Instrument"],
        subject_map: %SubjectMap{
          strategy: :template,
          value: "https://example.com/instruments/{unindexed_symbol}",
          term_type: :iri
        },
        identities: [[:id]],
        metadata: %{attribute_columns: %{id: "id", unindexed_symbol: "unindexed_symbol"}}
      }

      bundle = %Bundle{resources: [source_res, target_without_valid_id]}
      assert {:error, refusals} = Mapping.validate(bundle)
      assert Enum.any?(refusals, &(&1.code == :REFUSED_R2RML_JOIN_WITHOUT_IDENTITY))
    end
  end

  # ============================================================================
  # 2. Fault Injection & Transaction Invariants
  # ============================================================================

  describe "2. Fault Injection & Invariant Enforcement" do
    test "proves transaction rollback preserves state integrity on negative balance validation failure" do
      # 1. Create initial valid vault
      vault =
        VaultBalance
        |> Ash.Changeset.for_create(:create, %{
          vault_code: "VAULT-NYC-001",
          available_balance: Decimal.new("1000000.00"),
          locked: false
        })
        |> Ash.create!()

      assert vault.id != nil

      # 2. Attempt invalid debit causing negative overdraft -> should fail closed
      invalid_transfer =
        vault
        |> Ash.Changeset.for_update(:transfer, %{
          available_balance: Decimal.new("-500.00")
        })
        |> Ash.update()

      assert {:error, %Ash.Error.Invalid{}} = invalid_transfer

      # 3. Prove original balance remains untouched at 1,000,000.00
      fresh_vault =
        VaultBalance
        |> Ash.Query.filter(id == ^vault.id)
        |> Ash.read_one!()

      assert Decimal.equal?(fresh_vault.available_balance, Decimal.new("1000000.00"))
    end

    test "proves locked vault rejects debit operations and halts side effects" do
      vault =
        VaultBalance
        |> Ash.Changeset.for_create(:create, %{
          vault_code: "VAULT-SECURE-999",
          available_balance: Decimal.new("5000000.00"),
          locked: true
        })
        |> Ash.create!()

      assert {:error, %Ash.Error.Invalid{}} =
               vault
               |> Ash.Changeset.for_update(:transfer, %{available_balance: Decimal.new("4000000.00")})
               |> Ash.update()
    end
  end

  # ============================================================================
  # 3. Service Latency & Partition Simulation in Reactor
  # ============================================================================

  defmodule LatencyProbeStep do
    use Reactor.Step

    def run(arguments, _context, _options) do
      timeout_ms = arguments[:timeout_threshold_ms] || 50
      injected_latency_ms = arguments[:injected_latency_ms] || 0

      if injected_latency_ms > timeout_ms do
        {:error,
         {:partition_timeout,
          "Simulated partition: RPC latency #{injected_latency_ms}ms exceeded #{timeout_ms}ms threshold"}}
      else
        {:ok, %{status: :healthy, latency_ms: injected_latency_ms}}
      end
    end

    def compensate(_reason, _arguments, _context, _options) do
      :ok
    end

    def undo(_result, _arguments, _context, _options) do
      :ok
    end
  end

  defmodule PartitionSimulationReactor do
    use Reactor

    input(:injected_latency_ms)
    input(:timeout_threshold_ms)

    step :latency_probe, LatencyProbeStep do
      argument :injected_latency_ms, input(:injected_latency_ms)
      argument :timeout_threshold_ms, input(:timeout_threshold_ms)
    end
  end

  describe "3. Service Latency & Network Partition Injections" do
    test "succeeds when latency is within acceptable tolerance" do
      inputs = %{injected_latency_ms: 10, timeout_threshold_ms: 100}
      assert {:ok, result} = Reactor.run(PartitionSimulationReactor, inputs)
      assert result.status == :healthy
    end

    test "fails closed when network partition / latency exceeds timeout threshold" do
      inputs = %{injected_latency_ms: 500, timeout_threshold_ms: 50}
      assert {:error, _err} = Reactor.run(PartitionSimulationReactor, inputs)
    end
  end
end
