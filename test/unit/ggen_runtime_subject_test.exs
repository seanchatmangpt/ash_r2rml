# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.SubjectTest do
  use ExUnit.Case, async: true

  alias AshR2RML.GgenRuntime.Subject

  @sha String.duplicate("a", 40)

  test "admits exact repository subjects" do
    assert {:ok, %{repo: "seanchatmangpt/ash_r2rml", base: @sha, head: @sha}} =
             Subject.admit(%{repo: "seanchatmangpt/ash_r2rml", base: @sha, head: @sha})
  end

  test "refuses abbreviated heads" do
    assert {:error, :REFUSED_RUNTIME_HEAD_NOT_EXACT} =
             Subject.admit(%{repo: "seanchatmangpt/ash_r2rml", base: @sha, head: "abcdef0"})
  end
end
