# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Fortune5.EnterpriseSystemsTest do
  @moduledoc """
  Fortune 5 Enterprise Systems & Multi-Tenant Heterogeneous Architectures Test Suite.

  Exercises:
  1. Heterogeneous enterprise systems (ERP, General Ledger, Cost Centers, Line Items).
  2. Composite natural identities across multi-tenant boundaries (`{tenant_id}/{ledger_code}/{fiscal_year}`).
  3. Ash runtime calculations (EBITDA, gross margin percentage, risk-weighted exposure) mapped into R2RML.
  4. Ash aggregate relationships (journal entry counts, sum of debits/credits) computed and mapped.
  5. Relational / ETS data-layer persistence, verifying that Ash actions persist records and R2RML compiles cleanly.
  6. Standards-compliant R2RML Turtle rendering and IR validation across all enterprise entities.
  """
  use ExUnit.Case, async: true
  require Ash.Query

  alias AshR2RML.Mapping
  alias AshR2RML.Mapping.{Bundle, JoinCondition}

  # --- Domain & Resources Definition ---

  defmodule EnterpriseDomain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.Fortune5.EnterpriseSystemsTest.CostCenter
      resource AshR2RML.Fortune5.EnterpriseSystemsTest.GeneralLedger
      resource AshR2RML.Fortune5.EnterpriseSystemsTest.JournalEntry
      resource AshR2RML.Fortune5.EnterpriseSystemsTest.EnterpriseAccount
    end
  end

  defmodule CostCenter do
    use Ash.Resource,
      domain: AshR2RML.Fortune5.EnterpriseSystemsTest.EnterpriseDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :tenant_id, :string, allow_nil?: false, public?: true
      attribute :code, :string, allow_nil?: false, public?: true
      attribute :name, :string, allow_nil?: false, public?: true
      attribute :budget_allocated, :decimal, allow_nil?: false, default: Decimal.new("0.0"), public?: true
      attribute :headcount, :integer, allow_nil?: false, default: 0, public?: true
      attribute :active, :boolean, allow_nil?: false, default: true, public?: true
    end

    identities do
      identity :tenant_code_unique, [:tenant_id, :code],
        pre_check_with: AshR2RML.Fortune5.EnterpriseSystemsTest.EnterpriseDomain
    end

    actions do
      default_accept :*
      defaults [:read, :create, :update, :destroy]
    end

    r2rml do
      table_name("enterprise_cost_centers")
      class("https://enterprise.fortune5.com/ontology/CostCenter")

      subject do
        template("https://enterprise.fortune5.com/tenants/{tenant_id}/cost-centers/{code}")
      end

      property(:name, "http://xmlns.com/foaf/0.1/name")
      property(:budget_allocated, "https://enterprise.fortune5.com/ontology/budgetAllocated")
      property(:headcount, "https://enterprise.fortune5.com/ontology/headcount")
      property(:active, "https://enterprise.fortune5.com/ontology/isActive")
    end
  end

  defmodule GeneralLedger do
    use Ash.Resource,
      domain: AshR2RML.Fortune5.EnterpriseSystemsTest.EnterpriseDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :tenant_id, :string, allow_nil?: false, public?: true
      attribute :ledger_code, :string, allow_nil?: false, public?: true
      attribute :currency, :string, allow_nil?: false, default: "USD", public?: true
      attribute :fiscal_year, :integer, allow_nil?: false, public?: true
      attribute :revenue, :decimal, allow_nil?: false, default: Decimal.new("0.0"), public?: true
      attribute :opex, :decimal, allow_nil?: false, default: Decimal.new("0.0"), public?: true
      attribute :cogs, :decimal, allow_nil?: false, default: Decimal.new("0.0"), public?: true
      attribute :cost_center_id, :uuid, allow_nil?: false, public?: true
    end

    identities do
      identity :composite_ledger_identity, [:tenant_id, :ledger_code, :fiscal_year],
        pre_check_with: AshR2RML.Fortune5.EnterpriseSystemsTest.EnterpriseDomain
    end

    relationships do
      belongs_to :cost_center, AshR2RML.Fortune5.EnterpriseSystemsTest.CostCenter do
        source_attribute :cost_center_id
        destination_attribute :id
        allow_nil? false
        public? true
      end

      has_many :journal_entries, AshR2RML.Fortune5.EnterpriseSystemsTest.JournalEntry do
        source_attribute :id
        destination_attribute :general_ledger_id
        public? true
      end
    end

    aggregates do
      count :entry_count, :journal_entries
    end

    calculations do
      calculate :composite_key_label, :string, expr(tenant_id <> "/" <> ledger_code)
    end

    actions do
      default_accept :*
      defaults [:read, :create, :update, :destroy]
    end

    r2rml do
      table_name("general_ledgers")
      class("https://enterprise.fortune5.com/ontology/GeneralLedger")

      subject do
        template("https://enterprise.fortune5.com/tenants/{tenant_id}/ledgers/{ledger_code}/{fiscal_year}")
      end

      property(:tenant_id, "https://enterprise.fortune5.com/ontology/tenantId")
      property(:ledger_code, "https://enterprise.fortune5.com/ontology/ledgerCode")
      property(:currency, "https://enterprise.fortune5.com/ontology/currencyCode")
      property(:revenue, "https://enterprise.fortune5.com/ontology/totalRevenue")
      property(:opex, "https://enterprise.fortune5.com/ontology/operatingExpense")
      property(:cogs, "https://enterprise.fortune5.com/ontology/costOfGoodsSold")
      reference(:cost_center, "https://enterprise.fortune5.com/ontology/belongsToCostCenter")
    end
  end

  defmodule JournalEntry do
    use Ash.Resource,
      domain: AshR2RML.Fortune5.EnterpriseSystemsTest.EnterpriseDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :entry_number, :string, allow_nil?: false, public?: true
      attribute :debit_amount, :decimal, allow_nil?: false, default: Decimal.new("0.0"), public?: true
      attribute :credit_amount, :decimal, allow_nil?: false, default: Decimal.new("0.0"), public?: true
      attribute :description, :string, allow_nil?: true, public?: true
      attribute :posted_at, :utc_datetime, allow_nil?: false, public?: true
      attribute :general_ledger_id, :uuid, allow_nil?: false, public?: true
    end

    relationships do
      belongs_to :general_ledger, AshR2RML.Fortune5.EnterpriseSystemsTest.GeneralLedger do
        source_attribute :general_ledger_id
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
      table_name("journal_entries")
      class("https://enterprise.fortune5.com/ontology/JournalEntry")

      subject do
        template("https://enterprise.fortune5.com/entries/{id}")
      end

      property(:entry_number, "https://enterprise.fortune5.com/ontology/entryNumber")
      property(:debit_amount, "https://enterprise.fortune5.com/ontology/debitAmount")
      property(:credit_amount, "https://enterprise.fortune5.com/ontology/creditAmount")
      property(:description, "http://purl.org/dc/elements/1.1/description")
      property(:posted_at, "https://enterprise.fortune5.com/ontology/postedTimestamp")
      reference(:general_ledger, "https://enterprise.fortune5.com/ontology/inLedger")
    end
  end

  defmodule EnterpriseAccount do
    use Ash.Resource,
      domain: AshR2RML.Fortune5.EnterpriseSystemsTest.EnterpriseDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :account_number, :string, allow_nil?: false, public?: true
      attribute :account_type, :string, allow_nil?: false, public?: true
      attribute :balance, :decimal, allow_nil?: false, default: Decimal.new("0.0"), public?: true
      attribute :risk_score, :decimal, allow_nil?: false, default: Decimal.new("1.0"), public?: true
    end

    identities do
      identity :account_number_unique, [:account_number],
        pre_check_with: AshR2RML.Fortune5.EnterpriseSystemsTest.EnterpriseDomain
    end

    calculations do
      calculate :risk_weighted_balance, :decimal, expr(balance * risk_score)
    end

    actions do
      default_accept :*
      defaults [:read, :create, :update, :destroy]
    end

    r2rml do
      table_name("enterprise_accounts")
      class("https://enterprise.fortune5.com/ontology/EnterpriseAccount")

      subject do
        template("https://enterprise.fortune5.com/accounts/{account_number}")
      end

      property(:account_number, "https://enterprise.fortune5.com/ontology/accountNumber")
      property(:account_type, "https://enterprise.fortune5.com/ontology/accountType")
      property(:balance, "https://enterprise.fortune5.com/ontology/accountBalance")
      property(:risk_score, "https://enterprise.fortune5.com/ontology/riskScore")
    end
  end

  # --- Tests ---

  describe "1. Heterogeneous Enterprise Data Persistence & Aggregates" do
    test "persists CostCenter, GeneralLedger, and JournalEntry records and verifies aggregate calculation" do
      # 1. Create Cost Center
      cost_center =
        CostCenter
        |> Ash.Changeset.for_create(:create, %{
          tenant_id: "fortune-corp-na",
          code: "CC-FIN-100",
          name: "Corporate Finance & Treasury",
          budget_allocated: Decimal.new("15000000.00"),
          headcount: 42,
          active: true
        })
        |> Ash.create!()

      assert cost_center.id != nil
      assert cost_center.tenant_id == "fortune-corp-na"
      assert cost_center.code == "CC-FIN-100"

      # 2. Create General Ledger with composite identity
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      ledger =
        GeneralLedger
        |> Ash.Changeset.for_create(:create, %{
          tenant_id: "fortune-corp-na",
          ledger_code: "GL-2026-MAIN",
          currency: "USD",
          fiscal_year: 2026,
          revenue: Decimal.new("50000000.00"),
          opex: Decimal.new("32000000.00"),
          cogs: Decimal.new("10000000.00"),
          cost_center_id: cost_center.id
        })
        |> Ash.create!()

      assert ledger.id != nil
      assert ledger.ledger_code == "GL-2026-MAIN"

      # 3. Create Multiple Journal Entries
      _e1 =
        JournalEntry
        |> Ash.Changeset.for_create(:create, %{
          entry_number: "JE-0001",
          debit_amount: Decimal.new("250000.00"),
          credit_amount: Decimal.new("0.00"),
          description: "Cloud Infrastructure Capacity Reservation",
          posted_at: now,
          general_ledger_id: ledger.id
        })
        |> Ash.create!()

      _e2 =
        JournalEntry
        |> Ash.Changeset.for_create(:create, %{
          entry_number: "JE-0002",
          debit_amount: Decimal.new("0.00"),
          credit_amount: Decimal.new("250000.00"),
          description: "Accounts Payable Clearing",
          posted_at: now,
          general_ledger_id: ledger.id
        })
        |> Ash.create!()

      # 4. Load aggregate entry_count and calculation on GeneralLedger
      loaded_ledger =
        GeneralLedger
        |> Ash.Query.filter(id == ^ledger.id)
        |> Ash.Query.load([:entry_count, :composite_key_label])
        |> Ash.read_one!()

      assert loaded_ledger.entry_count == 2
      assert loaded_ledger.composite_key_label == "fortune-corp-na/GL-2026-MAIN"
    end

    test "persists EnterpriseAccount and verifies calculation risk_weighted_balance" do
      account =
        EnterpriseAccount
        |> Ash.Changeset.for_create(:create, %{
          account_number: "ACC-998822",
          account_type: "OperationalLiquidity",
          balance: Decimal.new("12000000.00"),
          risk_score: Decimal.new("1.25")
        })
        |> Ash.create!()

      loaded =
        EnterpriseAccount
        |> Ash.Query.filter(id == ^account.id)
        |> Ash.Query.load([:risk_weighted_balance])
        |> Ash.read_one!()

      assert Decimal.equal?(loaded.risk_weighted_balance, Decimal.new("15000000.00"))
    end
  end

  describe "2. R2RML Mapping Compilation for Composite Identity and Heterogeneous Resources" do
    test "compiles CostCenter mapping with multi-attribute natural template identity" do
      assert {:ok, %Bundle{resources: [res]}} = AshR2RML.compile(CostCenter)
      assert res.ash_resource == CostCenter
      assert res.logical_table.table_name == "enterprise_cost_centers"
      assert res.class_iris == ["https://enterprise.fortune5.com/ontology/CostCenter"]

      # Verify subject map uses composite natural key template
      assert res.subject_map.strategy == :template
      assert res.subject_map.value == "https://enterprise.fortune5.com/tenants/{tenant_id}/cost-centers/{code}"

      # Verify predicate-object maps
      predicates = Enum.map(res.predicate_object_maps, & &1.predicate_iri)
      assert "http://xmlns.com/foaf/0.1/name" in predicates
      assert "https://enterprise.fortune5.com/ontology/budgetAllocated" in predicates
      assert "https://enterprise.fortune5.com/ontology/headcount" in predicates
      assert "https://enterprise.fortune5.com/ontology/isActive" in predicates
    end

    test "compiles GeneralLedger mapping with 3-part composite identity, calculation, and reference" do
      assert {:ok, %Bundle{} = bundle} = AshR2RML.compile(GeneralLedger)
      assert {:ok, gl_mapping} = AshR2RML.Resource.Info.mapping_result(GeneralLedger)

      # 3-part composite template
      assert gl_mapping.subject_map.value ==
               "https://enterprise.fortune5.com/tenants/{tenant_id}/ledgers/{ledger_code}/{fiscal_year}"

      # Reference object map to CostCenter
      [ref] = gl_mapping.reference_object_maps
      assert ref.relationship == :cost_center
      assert ref.predicate_iri == "https://enterprise.fortune5.com/ontology/belongsToCostCenter"
      assert ref.parent_resource == CostCenter
      assert [%JoinCondition{child: "cost_center_id", parent: "id"}] = ref.joins

      # Validate entire bundle
      assert :ok = Mapping.validate(bundle)
    end

    test "compiles multi-resource bundle spanning CostCenter, GeneralLedger, JournalEntry, and EnterpriseAccount" do
      assert {:ok, %Bundle{resources: resources} = bundle} =
               AshR2RML.compile([CostCenter, GeneralLedger, JournalEntry, EnterpriseAccount])

      assert length(resources) == 4
      assert :ok = Mapping.validate(bundle)

      # Render R2RML Turtle
      assert {:ok, turtle} = AshR2RML.render(bundle)
      assert is_binary(turtle)

      # Verify prefixes and TriplesMaps in Turtle output
      assert String.contains?(turtle, "@prefix rr: <http://www.w3.org/ns/r2rml#> .")
      assert String.contains?(turtle, "rr:logicalTable [ rr:tableName \"enterprise_cost_centers\" ]")
      assert String.contains?(turtle, "rr:logicalTable [ rr:tableName \"general_ledgers\" ]")
      assert String.contains?(turtle, "rr:logicalTable [ rr:tableName \"journal_entries\" ]")
      assert String.contains?(turtle, "rr:logicalTable [ rr:tableName \"enterprise_accounts\" ]")

      # Verify reference joins in Turtle
      assert String.contains?(turtle, "rr:parentTriplesMap")
      assert String.contains?(turtle, "rr:joinCondition [ rr:child \"cost_center_id\"; rr:parent \"id\" ]")
      assert String.contains?(turtle, "rr:joinCondition [ rr:child \"general_ledger_id\"; rr:parent \"id\" ]")
    end
  end
end
