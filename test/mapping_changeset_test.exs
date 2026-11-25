# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Mapping.ChangesetTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Mapping.Changeset
  alias AshR2RML.RDF.GraphAlgebra
  alias RDF.Graph

  import RDF.Sigils

  @s ~I<urn:uuid:00000000-0000-0000-0000-000000000000>
  @s1 ~I<urn:uuid:00000000-0000-0000-0000-000000000001>
  @s2 ~I<urn:uuid:00000000-0000-0000-0000-000000000002>
  @p ~I<http://www.w3.org/2000/01/rdf-schema#label>
  @p1 ~I<http://xmlns.com/foaf/0.1/name>
  @p2 ~I<http://purl.org/dc/terms/title>
  @o ~I<urn:uuid:00000000-0000-0000-0000-0000000000f0>
  @o1 ~I<urn:uuid:00000000-0000-0000-0000-0000000000f1>
  @o2 ~I<urn:uuid:00000000-0000-0000-0000-0000000000f2>

  test "diff/2 computes real add/remove statements between two graphs" do
    old_graph = Graph.new({@s1, @p, @o1})

    new_graph =
      Graph.new([
        {@s1, @p, @o1},
        {@s2, @p, @o2}
      ])

    assert {:ok, %Changeset{} = changeset} = Changeset.diff(old_graph, new_graph)

    assert Enum.count(changeset.add) == 1
    assert {@s2, @p, @o2} in changeset.add
    assert is_nil(changeset.remove)
  end

  test "diff/2 detects a real removal" do
    old_graph =
      Graph.new([
        {@s1, @p, @o1},
        {@s2, @p, @o2}
      ])

    new_graph = Graph.new({@s1, @p, @o1})

    assert {:ok, %Changeset{} = changeset} = Changeset.diff(old_graph, new_graph)

    assert is_nil(changeset.add)
    assert Enum.count(changeset.remove) == 1
    assert {@s2, @p, @o2} in changeset.remove
  end

  test "diff/2 of identical graphs is empty" do
    graph = Graph.new({@s1, @p, @o1})

    assert {:ok, changeset} = Changeset.diff(graph, graph)
    assert Changeset.empty?(changeset)
  end

  test "new/1 refuses overlapping add/remove triples" do
    triple = {@s, @p, @o}

    assert {:error, refusal} =
             Changeset.new(add: Graph.new(triple), remove: Graph.new(triple))

    assert refusal.code == :REFUSED_CHANGESET_CONFLICT
  end

  test "new/1 refuses overlapping update/replace subjects" do
    subject = @s
    update_triple = {subject, @p1, @o1}
    replace_triple = {subject, @p2, @o2}

    assert {:error, refusal} =
             Changeset.new(update: Graph.new(update_triple), replace: Graph.new(replace_triple))

    assert refusal.code == :REFUSED_CHANGESET_CONFLICT
  end

  test "invert/1 swaps add and remove" do
    add_triple = {@s1, @p, @o1}
    remove_triple = {@s2, @p, @o2}

    {:ok, changeset} = Changeset.new(add: Graph.new(add_triple), remove: Graph.new(remove_triple))
    inverted = Changeset.invert(changeset)

    assert add_triple in inverted.remove
    assert remove_triple in inverted.add
  end

  test "inserts/1 unions add, update, and replace but excludes remove" do
    {:ok, changeset} =
      Changeset.new(
        add: Graph.new({@s1, @p, @o1}),
        remove: Graph.new({@s2, @p, @o2})
      )

    inserts = Changeset.inserts(changeset)
    assert {@s1, @p, @o1} in inserts
    refute {@s2, @p, @o2} in inserts
  end

  test "GraphAlgebra.graph_delete cleans up empty descriptions" do
    graph = Graph.new({@s, @p, @o})
    removal = Graph.new({@s, @p, @o})

    result = GraphAlgebra.graph_delete(graph, removal)
    assert Enum.empty?(result)
    refute @s in Graph.subjects(result)
  end

  test "GraphAlgebra.graph_intersection returns only shared statements" do
    left =
      Graph.new([
        {@s1, @p, @o1},
        {@s2, @p, @o2}
      ])

    right = Graph.new({@s1, @p, @o1})

    intersection = GraphAlgebra.graph_intersection(left, right)
    assert Enum.count(intersection) == 1
    assert {@s1, @p, @o1} in intersection
  end

  test "GraphAlgebra.equivalent?/2 is order-independent" do
    a =
      Graph.new([
        {@s1, @p, @o1},
        {@s2, @p, @o2}
      ])

    b =
      Graph.new([
        {@s2, @p, @o2},
        {@s1, @p, @o1}
      ])

    assert GraphAlgebra.equivalent?(a, b)
  end
end
