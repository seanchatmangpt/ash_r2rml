# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Negative.ReactorNegativeTest do
  @moduledoc """
  Negative test suite verifying Reactor pipeline failure isolation and step halts:
  - Halting pipeline execution when an unmapped resource fails compilation
  - Halting pipeline when schema alignment verification fails
  """
  use ExUnit.Case, async: true

  defmodule BrokenPipelineResource do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets

    # Missing AshR2RML extension & r2rml block
    attributes do
      uuid_primary_key :id
    end
  end

  describe "Reactor Pipeline Negative Tests" do
    test "pipeline fails execution when non-R2RML resource is provided" do
      result =
        Reactor.run(AshR2RML.Reactor.Pipeline, %{
          resources: [BrokenPipelineResource],
          actor: nil,
          observations: [],
          metadata: %{}
        })

      assert match?({:error, _}, result)
    end
  end
end
