# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Red3MaterializationDefaultsTest do
  # Not async: flips application env.
  use ExUnit.Case, async: false

  alias AshR2RML.{Delta, NQuads, Parity, Refusal}

  @s "http://schema.org/s"
  @p "http://schema.org/p"

  setup do
    prev_i = Application.get_env(:ash_r2rml, :max_materialization_items)
    prev_b = Application.get_env(:ash_r2rml, :max_materialization_bytes)

    on_exit(fn ->
      restore(:max_materialization_items, prev_i)
      restore(:max_materialization_bytes, prev_b)
    end)
  end

  defp restore(key, nil), do: Application.delete_env(:ash_r2rml, key)
  defp restore(key, value), do: Application.put_env(:ash_r2rml, key, value)

  defp graph(n, literal \\ "v") do
    Enum.reduce(1..n, RDF.Graph.new(), fn i, g ->
      RDF.Graph.add(g, {RDF.iri("#{@s}/#{i}"), RDF.iri(@p), RDF.literal("#{literal}#{i}")})
    end)
  end

  test "default item bound refuses oversized input with no :max given" do
    Application.put_env(:ash_r2rml, :max_materialization_items, 3)

    assert {:error, %Refusal{code: :REFUSED_RESOURCE_BOUND}} =
             Parity.compare(:sparql_sql, :s, Enum.map(1..4, &%{"x" => &1}), [])

    assert {:error, %Refusal{code: :REFUSED_RESOURCE_BOUND}} = Delta.diff(graph(1), graph(4))
    assert {:error, %Refusal{code: :REFUSED_RESOURCE_BOUND}} = Delta.root_digest(graph(4))

    quads = for i <- 1..4, do: {{:iri, "#{@s}/#{i}"}, @p, {:literal, "v"}, nil}
    assert {:error, %Refusal{code: :REFUSED_RESOURCE_BOUND}} = NQuads.lines(quads)
  end

  test "byte bound refuses a single huge term under a tiny item count" do
    Application.put_env(:ash_r2rml, :max_materialization_bytes, 1_000)
    big = String.duplicate("x", 5_000)

    assert {:error, %Refusal{code: :REFUSED_RESOURCE_BOUND}} = Delta.diff(graph(1), graph(1, big))

    assert {:error, %Refusal{code: :REFUSED_RESOURCE_BOUND}} =
             Parity.compare(:sparql_sql, :s, [%{"x" => big}], [])
  end

  test ":infinity opts out and a within-bound call still succeeds" do
    Application.put_env(:ash_r2rml, :max_materialization_items, 1)
    assert %{added: [_ | _]} = Delta.diff(graph(1), graph(3), max: :infinity)
    Application.put_env(:ash_r2rml, :max_materialization_items, 100)
    assert %{added: [_]} = Delta.diff(graph(1), graph(2))
  end
end
