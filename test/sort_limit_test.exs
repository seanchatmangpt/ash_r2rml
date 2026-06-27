# SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.SortLimitTest do
  @moduledoc """
  `LIMIT`/`OFFSET` must not be pushed to Cypher when the sort can't be (#407). An
  in-memory calculation sort (`score_doubled = score * 2`) doesn't render to an
  `ORDER BY`, so pushing the limit would truncate *unordered* rows — the data
  layer must instead apply the limit after its in-memory sort.
  """
  use ExUnit.Case, async: true
  require Ash.Query
  alias AshNeo4j.Sandbox
  alias AshNeo4j.Test.Resource.Comment

  setup_all do
    AshNeo4j.BoltyHelper.start()
  end

  setup do
    Sandbox.checkout()
    on_exit(&Sandbox.rollback/0)
  end

  test "sort by an in-memory calculation + limit returns the calculation's top-k" do
    # Titles ascend opposite to score, and Comment has a prepared `sort:
    # [title: :asc]` that *does* push down. So a limit pushed onto that partial
    # `ORDER BY s.title` would pick {a, b} (lowest scores); the score_doubled
    # top-2 is {c, b}. Only deferring the limit to the in-memory sort gives {c, b}.
    a = Comment |> Ash.create!(%{title: "a", score: 1})
    b = Comment |> Ash.create!(%{title: "b", score: 2})
    c = Comment |> Ash.create!(%{title: "c", score: 3})

    {:ok, results} =
      Comment
      |> Ash.Query.filter(id in ^[a.id, b.id, c.id])
      |> Ash.Query.sort(score_doubled: :desc)
      |> Ash.Query.limit(2)
      |> Ash.read()

    assert Enum.map(results, & &1.id) == [c.id, b.id]
  end
end
