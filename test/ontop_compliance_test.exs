# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OntopComplianceTest do
  use ExUnit.Case, async: true

  alias AshR2RML.OBDA.Ontop.Compliance

  test "pins the exact Ontop 5.5.0 source identity" do
    assert Compliance.version() == "5.5.0"

    assert Compliance.source_identity() == %{
             url: "https://ontop-vkg.org/guide/compliance.html",
             updated: "2026-07-21",
             ontop_version: "5.5.0"
           }
  end

  test "preserves the complete published SPARQL feature list without hiding exclusions" do
    # Ontop names 94 supported features. Summing its declared row numerators yields
    # 93 because the aggregate row says 6/6 while naming seven aggregate functions.
    assert Compliance.counts(:sparql_1_1) == %{supported: 94, unsupported: 8}

    assert Compliance.feature_status(:sparql_1_1, "BGP") == :supported
    assert Compliance.feature_status(:sparql_1_1, "DESCRIBE") == :supported
    assert Compliance.feature_status(:sparql_1_1, "ZeroOrMorePath") == :unsupported
    assert Compliance.feature_status(:sparql_1_1, "SERVICE") == :unsupported
    assert Compliance.feature_status(:sparql_1_1, "STRDT") == :unsupported
    assert Compliance.feature_status(:sparql_1_1, "timezone") == :unsupported
    assert Compliance.feature_status(:sparql_1_1, "user defined functions") == :unsupported

    {:ok, sparql} = Compliance.standard(:sparql_1_1)
    aggregate = sparql["11. Aggregates"]
    assert aggregate.coverage == "6/6"
    assert length(aggregate.supported) == 7
    assert aggregate.limitations != []
  end

  test "preserves the complete published GeoSPARQL list and supported units" do
    assert Compliance.counts(:geosparql_1_0) == %{supported: 37, unsupported: 32}

    assert Compliance.feature_status(:geosparql_1_0, "geo:asWKT") == :supported
    assert Compliance.feature_status(:geosparql_1_0, "geof:distance") == :supported
    assert Compliance.feature_status(:geosparql_1_0, "geof:rcc8ntppi") == :supported
    assert Compliance.feature_status(:geosparql_1_0, "geo:asGML") == :unsupported
    assert Compliance.feature_status(:geosparql_1_0, "geo:dimension") == :unsupported

    {:ok, geo} = Compliance.standard(:geosparql_1_0)
    assert geo.units == ["metre", "radian", "degree"]
  end

  test "R2RML exceptions remain explicit instead of being rounded up to full compliance" do
    {:ok, r2rml} = Compliance.standard(:r2rml)
    assert r2rml.status == :partial

    assert r2rml.unsupported == [
             "Base IRIs",
             "R2RML default mapping generation",
             "Normalization of binary SQL datatypes"
           ]

    for feature <- r2rml.unsupported do
      assert Compliance.feature_status(:r2rml, feature) == :unsupported
      assert {:error, refusal} = Compliance.require_supported(:r2rml, feature)
      assert refusal.code == :REFUSED_OBDA_CAPABILITY_UNSUPPORTED
    end
  end

  test "RDF 1.1, time functions, dialect limitations and 5.5.0 functions are inspectable" do
    {:ok, rdf} = Compliance.standard(:rdf_1_1)
    assert rdf.status == :supported
    assert length(rdf.semantics) == 2

    {:ok, time} = Compliance.standard(:time_functions)
    assert length(time.supported) == 20
    assert time.limitations.postgres_granularity_aliases["millisecond"] == "milliseconds"
    assert "Oracle" in time.limitations.mixed_date_datetime_ofn

    assert Compliance.feature_status(:other_functions, "xsd:date") == :supported
    assert Compliance.feature_status(:other_functions, "obdaf:queryId") == :supported
  end

  test "capability admission is fail-closed" do
    assert {:ok, admitted} = Compliance.require_supported(:sparql_1_1, "SELECT")
    assert admitted.engine == :ontop
    assert admitted.version == "5.5.0"

    assert {:error, unsupported} = Compliance.require_supported(:sparql_1_1, "SERVICE")
    assert unsupported.code == :REFUSED_OBDA_CAPABILITY_UNSUPPORTED

    assert {:error, unknown} = Compliance.require_supported(:sparql_1_1, "SPARQL 9.9 teleport")
    assert unknown.code == :REFUSED_OBDA_CAPABILITY_UNKNOWN

    assert {:error, unknown_standard} = Compliance.standard(:invented_standard)
    assert unknown_standard.code == :REFUSED_OBDA_CAPABILITY_UNKNOWN
  end

  test "every published supported SPARQL and GeoSPARQL section has a live crown probe" do
    assert Compliance.unprobed_supported_sections(:sparql_1_1) == []
    assert Compliance.unprobed_supported_sections(:geosparql_1_0) == []
  end

  test "all live crown queries are admitted by the local SPARQL language boundary" do
    for probe <- Compliance.protocol_probes() do
      assert {:ok, query} = AshR2RML.SPARQL.Query.admit(probe.query),
             "probe #{probe.id} was not admitted"

      assert is_binary(query.sha256)
      assert byte_size(query.sha256) == 64
    end
  end

  test "AshR2RML itself refuses opaque binary fallback rather than claiming Ontop normalization" do
    refute AshR2RML.Datatype.Registry.supported?(:binary)

    assert {:error, refusal} = AshR2RML.Datatype.Registry.resolve(:binary)
    assert refusal.code == :UNSUPPORTED_ASH_TYPE
  end
end
