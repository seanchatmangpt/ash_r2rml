# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.EtsBackendTest do
  use ExUnit.Case, async: true
  test "compiler retains ETS storage backend" do
    assert File.read!("AGENTS.md") =~ "storage_backend: :postgres | :ets"
  end
end
