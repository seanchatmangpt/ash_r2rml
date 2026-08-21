# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Fortune5.MeasurementAndQUDTTest do
  @moduledoc """
  Fortune 5 Telemetry, APM Metrics & Strict QUDT Unit Bindings Test Suite.

  Exercises:
  1. Strict QUDT (Quantities, Units, Dimensions and Data Types) ontology bindings:
     - `unit:MilliSEC` (http://qudt.org/vocab/unit/MilliSEC)
     - `unit:PERCENT` (http://qudt.org/vocab/unit/PERCENT)
     - `unit:MegaBYTE` (http://qudt.org/vocab/unit/MegaBYTE)
     - `unit:NUM-PER-SEC` (http://qudt.org/vocab/unit/NUM-PER-SEC)
  2. Custom Ash scalar types implementing `AshR2RML.Type` behaviour with QUDT datatypes.
  3. Explicit datatype resolution through `AshR2RML.Datatype.Registry`.
  4. R2RML PredicateObjectMap generation with explicit `rr:datatype` pointing to QUDT units.
  5. APM Latency, Throughput, and SLO Availability metric persistence and validation.
  """
  use ExUnit.Case, async: true
  require Ash.Query

  alias AshR2RML.Datatype.Registry, as: DatatypeRegistry
  alias AshR2RML.Mapping
  alias AshR2RML.Mapping.Bundle

  # ============================================================================
  # 1. Custom Ash Types Implementing AshR2RML.Type Behaviour
  # ============================================================================

  defmodule QudtMilliSeconds do
    use Ash.Type
    use AshR2RML.Type, xsd_datatype: "http://qudt.org/vocab/unit/MilliSEC"

    @impl Ash.Type
    def storage_type(_), do: :decimal

    @impl Ash.Type
    def cast_input(value, _) do
      case Decimal.cast(value) do
        {:ok, decimal} -> {:ok, decimal}
        :error -> {:error, "Invalid milliseconds decimal value"}
      end
    end

    @impl Ash.Type
    def cast_stored(nil, _), do: {:ok, nil}
    def cast_stored(value, _), do: Decimal.cast(value)

    @impl Ash.Type
    def dump_to_native(nil, _), do: {:ok, nil}
    def dump_to_native(value, _), do: Decimal.cast(value)

    @impl AshR2RML.Type
    def to_rdf_lexical(decimal), do: Decimal.to_string(decimal)
  end

  defmodule QudtPercentage do
    use Ash.Type
    use AshR2RML.Type, xsd_datatype: "http://qudt.org/vocab/unit/PERCENT"

    @impl Ash.Type
    def storage_type(_), do: :float

    @impl Ash.Type
    def cast_input(value, _) when is_number(value), do: {:ok, value / 1.0}

    def cast_input(value, _) when is_binary(value) do
      case Float.parse(value) do
        {float, _} -> {:ok, float}
        :error -> {:error, "Invalid percentage value"}
      end
    end

    @impl Ash.Type
    def cast_stored(nil, _), do: {:ok, nil}
    def cast_stored(value, _), do: {:ok, value / 1.0}

    @impl Ash.Type
    def dump_to_native(nil, _), do: {:ok, nil}
    def dump_to_native(value, _), do: {:ok, value / 1.0}

    @impl AshR2RML.Type
    def to_rdf_lexical(float), do: Float.to_string(float)
  end

  # ============================================================================
  # 2. Domain & Resources Definition
  # ============================================================================

  defmodule TelemetryDomain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.Fortune5.MeasurementAndQUDTTest.LatencyMetric
      resource AshR2RML.Fortune5.MeasurementAndQUDTTest.ThroughputMetric
      resource AshR2RML.Fortune5.MeasurementAndQUDTTest.SLOAvailabilityMetric
    end
  end

  defmodule LatencyMetric do
    use Ash.Resource,
      domain: AshR2RML.Fortune5.MeasurementAndQUDTTest.TelemetryDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :service_name, :string, allow_nil?: false, public?: true
      attribute :metric_window, :string, allow_nil?: false, default: "1m", public?: true

      attribute :p50_latency_ms, AshR2RML.Fortune5.MeasurementAndQUDTTest.QudtMilliSeconds,
        allow_nil?: false,
        public?: true

      attribute :p90_latency_ms, AshR2RML.Fortune5.MeasurementAndQUDTTest.QudtMilliSeconds,
        allow_nil?: false,
        public?: true

      attribute :p99_latency_ms, AshR2RML.Fortune5.MeasurementAndQUDTTest.QudtMilliSeconds,
        allow_nil?: false,
        public?: true
    end

    identities do
      identity :service_window_unique, [:service_name, :metric_window],
        pre_check_with: AshR2RML.Fortune5.MeasurementAndQUDTTest.TelemetryDomain
    end

    actions do
      default_accept :*
      defaults [:read, :create, :update, :destroy]
    end

    r2rml do
      table_name("apm_latency_metrics")
      class("https://telemetry.fortune5.com/ontology/LatencyMetric")

      subject do
        template("https://telemetry.fortune5.com/services/{service_name}/latency/{metric_window}")
      end

      property(:service_name, "https://telemetry.fortune5.com/ontology/serviceName")

      property(:p50_latency_ms, "https://telemetry.fortune5.com/ontology/p50Latency",
        datatype: "http://qudt.org/vocab/unit/MilliSEC"
      )

      property(:p90_latency_ms, "https://telemetry.fortune5.com/ontology/p90Latency",
        datatype: "http://qudt.org/vocab/unit/MilliSEC"
      )

      property(:p99_latency_ms, "https://telemetry.fortune5.com/ontology/p99Latency",
        datatype: "http://qudt.org/vocab/unit/MilliSEC"
      )
    end
  end

  defmodule ThroughputMetric do
    use Ash.Resource,
      domain: AshR2RML.Fortune5.MeasurementAndQUDTTest.TelemetryDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :service_name, :string, allow_nil?: false, public?: true
      attribute :requests_per_sec, :decimal, allow_nil?: false, default: Decimal.new("0.0"), public?: true
      attribute :bandwidth_mb, :decimal, allow_nil?: false, default: Decimal.new("0.0"), public?: true
    end

    identities do
      identity :service_throughput_unique, [:service_name],
        pre_check_with: AshR2RML.Fortune5.MeasurementAndQUDTTest.TelemetryDomain
    end

    actions do
      default_accept :*
      defaults [:read, :create, :update, :destroy]
    end

    r2rml do
      table_name("apm_throughput_metrics")
      class("https://telemetry.fortune5.com/ontology/ThroughputMetric")

      subject do
        template("https://telemetry.fortune5.com/services/{service_name}/throughput")
      end

      property(:service_name, "https://telemetry.fortune5.com/ontology/serviceName")

      property(:requests_per_sec, "https://telemetry.fortune5.com/ontology/requestsPerSecond",
        datatype: "http://qudt.org/vocab/unit/NUM-PER-SEC"
      )

      property(:bandwidth_mb, "https://telemetry.fortune5.com/ontology/bandwidthRate",
        datatype: "http://qudt.org/vocab/unit/MegaBYTE"
      )
    end
  end

  defmodule SLOAvailabilityMetric do
    use Ash.Resource,
      domain: AshR2RML.Fortune5.MeasurementAndQUDTTest.TelemetryDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :service_name, :string, allow_nil?: false, public?: true
      attribute :uptime_pct, AshR2RML.Fortune5.MeasurementAndQUDTTest.QudtPercentage, allow_nil?: false, public?: true

      attribute :error_budget_pct, AshR2RML.Fortune5.MeasurementAndQUDTTest.QudtPercentage,
        allow_nil?: false,
        public?: true
    end

    identities do
      identity :service_slo_unique, [:service_name],
        pre_check_with: AshR2RML.Fortune5.MeasurementAndQUDTTest.TelemetryDomain
    end

    actions do
      default_accept :*
      defaults [:read, :create, :update, :destroy]
    end

    r2rml do
      table_name("apm_slo_metrics")
      class("https://telemetry.fortune5.com/ontology/SLOAvailabilityMetric")

      subject do
        template("https://telemetry.fortune5.com/services/{service_name}/slo")
      end

      property(:service_name, "https://telemetry.fortune5.com/ontology/serviceName")

      property(:uptime_pct, "https://telemetry.fortune5.com/ontology/uptimePercentage",
        datatype: "http://qudt.org/vocab/unit/PERCENT"
      )

      property(:error_budget_pct, "https://telemetry.fortune5.com/ontology/errorBudgetRemaining",
        datatype: "http://qudt.org/vocab/unit/PERCENT"
      )
    end
  end

  # ============================================================================
  # Tests
  # ============================================================================

  describe "1. QUDT Custom Ash.Type & Datatype Registry Resolutions" do
    test "resolves custom Ash.Type implementing AshR2RML.Type behaviour to QUDT datatypes" do
      assert {:ok, dt_ms} = DatatypeRegistry.resolve(QudtMilliSeconds)
      assert dt_ms.rdf_datatype == "http://qudt.org/vocab/unit/MilliSEC"

      assert {:ok, dt_pct} = DatatypeRegistry.resolve(QudtPercentage)
      assert dt_pct.rdf_datatype == "http://qudt.org/vocab/unit/PERCENT"
    end

    test "resolves explicit QUDT datatype overrides on standard scalar types" do
      assert {:ok, dt_rps} = DatatypeRegistry.resolve(:decimal, "http://qudt.org/vocab/unit/NUM-PER-SEC")
      assert dt_rps.rdf_datatype == "http://qudt.org/vocab/unit/NUM-PER-SEC"

      assert {:ok, dt_mb} = DatatypeRegistry.resolve(:decimal, "http://qudt.org/vocab/unit/MegaBYTE")
      assert dt_mb.rdf_datatype == "http://qudt.org/vocab/unit/MegaBYTE"
    end
  end

  describe "2. Data Persistence with Custom QUDT Types" do
    test "persists LatencyMetric and SLOAvailabilityMetric records with custom QUDT types" do
      latency =
        LatencyMetric
        |> Ash.Changeset.for_create(:create, %{
          service_name: "order-checkout-api",
          metric_window: "1m",
          p50_latency_ms: Decimal.new("14.50"),
          p90_latency_ms: Decimal.new("42.10"),
          p99_latency_ms: Decimal.new("89.75")
        })
        |> Ash.create!()

      assert latency.id != nil
      assert Decimal.equal?(latency.p50_latency_ms, Decimal.new("14.50"))
      assert Decimal.equal?(latency.p99_latency_ms, Decimal.new("89.75"))

      slo =
        SLOAvailabilityMetric
        |> Ash.Changeset.for_create(:create, %{
          service_name: "order-checkout-api",
          uptime_pct: 99.985,
          error_budget_pct: 70.0
        })
        |> Ash.create!()

      assert slo.id != nil
      assert slo.uptime_pct == 99.985
    end
  end

  describe "3. R2RML Mapping & Strict QUDT Datatype Serialization" do
    test "compiles bundle and verifies QUDT datatypes in mapping IR" do
      assert {:ok, %Bundle{resources: resources} = bundle} =
               AshR2RML.compile([LatencyMetric, ThroughputMetric, SLOAvailabilityMetric])

      assert length(resources) == 3
      assert :ok = Mapping.validate(bundle)

      # 1. Verify LatencyMetric IR
      {:ok, latency_map} = AshR2RML.Resource.Info.mapping_result(LatencyMetric)
      p50_map = Enum.find(latency_map.predicate_object_maps, &(&1.attribute == :p50_latency_ms))
      assert p50_map.object_map.datatype.rdf_datatype == "http://qudt.org/vocab/unit/MilliSEC"

      # 2. Verify ThroughputMetric IR
      {:ok, tp_map} = AshR2RML.Resource.Info.mapping_result(ThroughputMetric)
      rps_map = Enum.find(tp_map.predicate_object_maps, &(&1.attribute == :requests_per_sec))
      assert rps_map.object_map.datatype.rdf_datatype == "http://qudt.org/vocab/unit/NUM-PER-SEC"

      bw_map = Enum.find(tp_map.predicate_object_maps, &(&1.attribute == :bandwidth_mb))
      assert bw_map.object_map.datatype.rdf_datatype == "http://qudt.org/vocab/unit/MegaBYTE"

      # 3. Verify SLOAvailabilityMetric IR
      {:ok, slo_map} = AshR2RML.Resource.Info.mapping_result(SLOAvailabilityMetric)
      uptime_map = Enum.find(slo_map.predicate_object_maps, &(&1.attribute == :uptime_pct))
      assert uptime_map.object_map.datatype.rdf_datatype == "http://qudt.org/vocab/unit/PERCENT"
    end

    test "renders R2RML Turtle with exact QUDT rr:datatype annotations" do
      assert {:ok, %Bundle{} = bundle} =
               AshR2RML.compile([LatencyMetric, ThroughputMetric, SLOAvailabilityMetric])

      assert {:ok, turtle} = AshR2RML.render(bundle)
      assert is_binary(turtle)

      # Verify QUDT datatypes rendered in Turtle
      assert String.contains?(turtle, "rr:datatype <http://qudt.org/vocab/unit/MilliSEC>")
      assert String.contains?(turtle, "rr:datatype <http://qudt.org/vocab/unit/PERCENT>")
      assert String.contains?(turtle, "rr:datatype <http://qudt.org/vocab/unit/NUM-PER-SEC>")
      assert String.contains?(turtle, "rr:datatype <http://qudt.org/vocab/unit/MegaBYTE>")

      # Verify logical tables and subject templates
      assert String.contains?(turtle, "rr:tableName \"apm_latency_metrics\"")
      assert String.contains?(turtle, "rr:tableName \"apm_throughput_metrics\"")
      assert String.contains?(turtle, "rr:tableName \"apm_slo_metrics\"")
    end
  end
end
