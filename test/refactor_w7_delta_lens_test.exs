# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW7DeltaLensTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Mapping.Changeset
  alias AshR2RML.Refusal

  test "Changeset.new/1 refuses a non-keyword list instead of raising" do
    assert {:error, %Refusal{}} = Changeset.new([1, 2, 3])
    assert {:error, %Refusal{}} = Changeset.new([{"add", nil}])
  end

  test "Changeset.new/1 still accepts keyword and map options" do
    assert {:ok, %Changeset{add: nil}} = Changeset.new([])
    assert {:ok, %Changeset{}} = Changeset.new(%{add: nil})
    assert {:error, %Refusal{}} = Changeset.new(add: :nope)
  end
end
