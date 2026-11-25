defmodule AshR2RML.WS5.SparkDependencyTest do
  use ExUnit.Case, async: true

  test "Spark is resolved at >= 2.7.0 and the DSL extension is a real Spark extension" do
    {:ok, applications} = :application.get_key(:ash_r2rml, :applications)
    assert :spark in applications
    assert {:module, Spark.Dsl.Extension} = Code.ensure_loaded(Spark.Dsl.Extension)
    assert {:module, AshR2RML.Resource} = Code.ensure_loaded(AshR2RML.Resource)

    {:ok, vsn} = :application.get_key(:spark, :vsn)
    assert Version.compare(to_string(vsn), "2.7.0") in [:gt, :eq]
  end
end
