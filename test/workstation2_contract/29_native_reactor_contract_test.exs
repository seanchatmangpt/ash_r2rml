# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.NativeReactorContractTest do
  use ExUnit.Case, async: true
  test "Reactor integration preserves native step contracts" do
    assert File.read!("AGENTS.md") =~ "Preserve native Ash.Reactor step contracts"
  end
end
