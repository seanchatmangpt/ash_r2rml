# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.ObservabilityTest do
  use ExUnit.Case, async: true

  alias AshR2RML.GgenRuntime.Observability

  test "same evidence identities replay to same digest" do
    input = %{correlation_id: "c1", trace_id: "t1", evidence: "ggen/ecosystem/ocel/current"}
    assert {:ok, first} = Observability.admit(input)
    assert {:ok, second} = Observability.admit(input)
    assert first.observation_digest == second.observation_digest
  end

  test "missing evidence fails closed" do
    assert {:error, :REFUSED_RUNTIME_OBSERVABILITY_INCOMPLETE} =
             Observability.admit(%{correlation_id: "c1", trace_id: "t1"})
  end
end
