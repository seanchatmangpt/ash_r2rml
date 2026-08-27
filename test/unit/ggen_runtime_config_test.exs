# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.ConfigTest do
  use ExUnit.Case, async: true
  alias AshR2RML.GgenRuntime.Config

  test "configuration identity replays deterministically" do
    input = %{dependencies: %{ash: "3.32.0"}, runtime: %{otp: "27", elixir: "1.18.4"}}
    assert {:ok, first} = Config.admit(input)
    assert {:ok, second} = Config.admit(input)
    assert first == second
    assert byte_size(first.dependency_digest) == 64
    assert byte_size(first.runtime_config_digest) == 64
  end

  test "empty dependency world is refused" do
    assert {:error, :REFUSED_RUNTIME_CONFIG_INCOMPLETE} = Config.admit(%{dependencies: %{}, runtime: %{otp: "27"}})
  end
end
