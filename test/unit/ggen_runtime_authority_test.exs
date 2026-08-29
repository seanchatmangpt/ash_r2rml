# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.AuthorityTest do
  use ExUnit.Case, async: true

  alias AshR2RML.GgenRuntime.Authority

  test "admits construct authority without direct actuation" do
    assert {:ok, %{action: :construct, direct_actuation: false}} =
             Authority.admit(%{policy: "project2", action: :construct})
  end

  test "refuses DO authority" do
    assert {:error, :REFUSED_RUNTIME_AMBIENT_DO_AUTHORITY} =
             Authority.admit(%{policy: "project2", action: :do})
  end
end
