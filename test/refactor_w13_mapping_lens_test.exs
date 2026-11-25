# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW13MappingLensTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Mapping.Changeset
  alias AshR2RML.Refusal

  test "unknown changeset option keys are refused, not silently dropped" do
    assert {:error, %Refusal{code: :REFUSED_CHANGESET_CONFLICT, evidence: %{unknown_keys: [":ad"]}}} =
             Changeset.new(ad: RDF.Graph.new())

    assert {:error, %Refusal{code: :REFUSED_CHANGESET_CONFLICT}} = Changeset.new(%{bogus: nil})
  end

  test "known action keys still build" do
    assert {:ok, %Changeset{add: nil}} = Changeset.new(add: nil)
  end
end
