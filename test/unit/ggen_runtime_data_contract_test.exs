# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.DataContractTest do
  use ExUnit.Case, async: true

  alias AshR2RML.GgenRuntime.DataContract

  test "admits explicit input and output schemas" do
    assert {:ok, contract} = DataContract.admit(%{input_schema: %{id: :uuid}, output_schema: %{name: :string}})
    assert contract.input_normalization == :explicit
    assert contract.output_sanitization == :explicit
  end

  test "refuses one-sided schema contracts" do
    assert {:error, :REFUSED_RUNTIME_SCHEMA_CONTRACT_INCOMPLETE} =
             DataContract.admit(%{input_schema: %{id: :uuid}})
  end
end
