# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.DfCMTest do
  use ExUnit.Case, async: true

  alias AshR2RML.DfCM
  alias AshR2RML.Production

  test "production design space remains combinatorial until bounded selection" do
    space = Production.design_space()

    assert DfCM.logical_cardinality(space) > 1_000_000

    selection = Production.default_assignment()
    assert DfCM.logical_cardinality(space, selection) == 1

    assert {:ok, [candidate], receipt} = DfCM.enumerate(space, select: selection)
    assert candidate.assignment == selection
    assert receipt.examined == 1
    assert receipt.admitted == 1
    refute receipt.truncated
  end

  test "string selections resolve only against already admitted atoms" do
    space = Production.design_space()

    selection =
      Production.default_assignment()
      |> Map.new(fn {key, value} -> {Atom.to_string(key), Atom.to_string(value)} end)

    assert {:ok, [candidate], _receipt} = DfCM.enumerate(space, select: selection)
    assert candidate.assignment == Production.default_assignment()
  end

  test "unknown dimension and option fail closed" do
    space = Production.design_space()

    assert {:error, %DfCM.Refusal{code: :REFUSED_DFCM_UNKNOWN_DIMENSION}} =
             DfCM.enumerate(space, select: %{"made_up_dimension" => "value"})

    assert {:error, %DfCM.Refusal{code: :REFUSED_DFCM_UNKNOWN_OPTION}} =
             DfCM.enumerate(space, select: %{control_plane: "made_up"})
  end

  test "cross-dimensional constraints reject unlawful candidates" do
    space = Production.design_space()

    assignment =
      Production.default_assignment()
      |> Map.put(:deployment_topology, :cellular)
      |> Map.put(:control_plane, :regional)

    assert {:error, refusals} = DfCM.admit(space, assignment)
    assert Enum.any?(refusals, &(&1.subject == :cellular_requires_cellular_control))
  end

  test "receipted writes require replay-capable recovery" do
    space = Production.design_space()

    assignment =
      Production.default_assignment()
      |> Map.put(:execution_mode, :receipted_write_runtime)
      |> Map.put(:recovery_strategy, :restart)

    assert {:error, refusals} = DfCM.admit(space, assignment)
    assert Enum.any?(refusals, &(&1.subject == :write_runtime_requires_replay))
  end

  test "selection is a separate authority-bearing receipt" do
    space = Production.design_space()
    assert {:ok, [candidate], _} = DfCM.enumerate(space, select: Production.default_assignment())

    assert {:error, %DfCM.Refusal{code: :REFUSED_DFCM_SELECTION_WITHOUT_AUTHORITY}} =
             DfCM.select(space, candidate, %{})

    assert {:ok, receipt} =
             DfCM.select(space, candidate, %{authorized?: true, receipt_sha256: String.duplicate("a", 64)})

    assert receipt.candidate_id == candidate.id
    assert is_binary(receipt.receipt_sha256)
  end

  test "bounded exploration reports truncation rather than pretending exhaustive search" do
    space = Production.design_space()

    assert {:ok, candidates, receipt} =
             DfCM.enumerate(space,
               select: %{deployment_topology: :active_passive},
               max_examined: 10,
               max_candidates: 10
             )

    assert length(candidates) <= 10
    assert receipt.examined <= 10
    assert receipt.truncated
    assert receipt.logical_cardinality > receipt.examined
  end
end
