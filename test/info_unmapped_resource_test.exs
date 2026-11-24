# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.InfoUnmappedResourceTest do
  @moduledoc """
  `AshR2RML.Resource.Info` over a plain Ash resource without the AshR2RML extension:
  every query function returns a typed error / nil / false / [] and never raises.
  """
  use ExUnit.Case, async: true

  alias AshR2RML.Resource.Info

  defmodule Plain do
    use Ash.Resource, domain: nil, data_layer: Ash.DataLayer.Ets

    attributes do
      uuid_primary_key :id
      attribute :name, :string, public?: true
    end
  end

  test "mapping_result/1 returns a typed refusal" do
    assert {:error, %AshR2RML.Refusal{}} = Info.mapping_result(Plain)
  end

  test "mapping/1 returns nil" do
    assert Info.mapping(Plain) == nil
  end

  test "mapped?/1 returns false" do
    assert Info.mapped?(Plain) == false
  end

  test "sparql_queries/1 returns []" do
    assert Info.sparql_queries(Plain) == []
  end

  test "mapping!/1 raises only the typed ArgumentError" do
    assert_raise ArgumentError, fn -> Info.mapping!(Plain) end
  end
end
