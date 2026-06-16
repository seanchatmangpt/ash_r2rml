# SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.BulkDestroyTest do
  @moduledoc """
  Bulk destroy (#361): `Ash.bulk_destroy` with the `:atomic` strategy deletes every
  node matching the query in one `MATCH (n:L) WHERE <filter> DETACH DELETE n` — via
  `destroy_query/4`. A `guard`-protected node is skipped, not deleted ("delete what
  is safe"); single targeted destroys keep erroring on a guard (separate path).
  """
  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Sandbox
  alias AshNeo4j.Test.Resource.Comment
  alias AshNeo4j.Test.Resource.Specification

  use ExUnit.Case, async: false

  require Ash.Query

  setup_all do
    BoltyHelper.start()
    :ok
  end

  setup do
    Sandbox.checkout()
    on_exit(&Sandbox.rollback/0)
  end

  test "deletes exactly the nodes matching the query filter, returning them" do
    for score <- [1, 5, 50, 200], do: Comment |> Ash.create!(%{title: "t", score: score})

    result =
      Comment
      |> Ash.Query.filter(score < 100)
      |> Ash.bulk_destroy!(:destroy, %{}, strategy: :atomic, return_records?: true, return_errors?: true)

    assert result.status == :success
    assert result.records |> Enum.map(& &1.score) |> Enum.sort() == [1, 5, 50]

    # Only the out-of-scope node survives.
    assert Comment |> Ash.read!() |> Enum.map(& &1.score) == [200]
  end

  test "skips a guard-protected node and deletes the rest" do
    free = Specification |> Ash.create!(%{type: :service})
    guarded = Specification |> Ash.create!(%{type: :resource})

    # `Specification` guards `SPECIFIES -> :Service`: a spec that specifies a
    # service must not be deleted. Seed that edge on `guarded` only.
    Sandbox.run(
      "MATCH (n:SRM:Specification {uuid: $id}) CREATE (n)-[:SPECIFIES]->(:Service)",
      %{"id" => guarded.id}
    )

    result = Ash.bulk_destroy!(Specification, :destroy, %{}, strategy: :atomic, return_records?: true)

    assert result.records |> Enum.map(& &1.id) == [free.id]

    # The guarded spec survives; the free one is gone.
    assert Specification |> Ash.read!() |> Enum.map(& &1.id) == [guarded.id]
  end
end
