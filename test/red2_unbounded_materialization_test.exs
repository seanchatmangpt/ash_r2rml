# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# RED phase: Parity/Delta/NQuads materialize unbounded inputs (expected typed
# REFUSED_RESOURCE_BOUND with a `:max` option), and the SPARQL protocol client
# drops the caller :timeout before the worker deadline is computed.
defmodule AshR2RML.Red2UnboundedMaterializationTest do
  use ExUnit.Case, async: true

  alias AshR2RML.{Delta, NQuads, Parity, Refusal}
  alias AshR2RML.SPARQL.{Local, Protocol}

  @pred {:iri, "https://schema.org/value"}

  defp quads(n) do
    for i <- 1..n do
      {{:iri, "urn:uuid:00000000-0000-0000-0000-#{String.pad_leading("#{i}", 12, "0")}"}, @pred, {:literal, "v#{i}"},
       nil}
    end
  end

  defp graph(n) do
    Enum.reduce(1..n, RDF.Graph.new(), fn i, g ->
      RDF.Graph.add(
        g,
        {RDF.iri("urn:uuid:00000000-0000-0000-0000-#{String.pad_leading("#{i}", 12, "0")}"),
         RDF.iri("https://schema.org/value"), RDF.literal(i)}
      )
    end)
  end

  defp rows(n), do: for(i <- 1..n, do: %{"x" => i})

  # Calls go through apply/3 so a missing bounded arity is a runtime failure of the
  # test (the finding), not a compile break of the suite.
  defp call(mod, fun, args), do: apply(mod, fun, args)

  test "NQuads.serialize/2 refuses over :max quads with REFUSED_RESOURCE_BOUND" do
    assert {:error, %Refusal{code: :REFUSED_RESOURCE_BOUND}} =
             call(NQuads, :serialize, [quads(5), [max: 2]])
  end

  test "NQuads.serialize/2 under :max returns the same output as serialize/1" do
    {:ok, expected} = NQuads.serialize(quads(3))
    assert {:ok, ^expected} = call(NQuads, :serialize, [quads(3), [max: 10]])
  end

  test "NQuads.lines/2 refuses over :max quads with REFUSED_RESOURCE_BOUND" do
    assert {:error, %Refusal{code: :REFUSED_RESOURCE_BOUND}} =
             call(NQuads, :lines, [quads(5), [max: 2]])
  end

  test "NQuads.escape_iri keeps astral codepoints intact" do
    iri = "urn:uuid:x-\u{1F600}\u{10FFFF}"
    assert {:ok, out} = NQuads.serialize([{{:iri, iri}, @pred, {:literal, "a"}, nil}])
    assert out =~ "<" <> iri <> ">"
  end

  test "Parity.compare/6 refuses over :max rows with REFUSED_RESOURCE_BOUND" do
    assert {:error, %Refusal{code: :REFUSED_RESOURCE_BOUND}} =
             call(Parity, :compare, [:sparql_sql, "s", rows(5), rows(1), %{}, [max: 2]])
  end

  test "Parity.compare/6 bounds the right side too" do
    assert {:error, %Refusal{code: :REFUSED_RESOURCE_BOUND}} =
             call(Parity, :compare, [:sparql_sql, "s", rows(1), rows(5), %{}, [max: 2]])
  end

  test "Delta.diff/3 refuses over :max triples with REFUSED_RESOURCE_BOUND" do
    assert {:error, %Refusal{code: :REFUSED_RESOURCE_BOUND}} =
             call(Delta, :diff, [graph(1), graph(5), [max: 2]])
  end

  test "Delta.root_digest/2 refuses over :max triples with REFUSED_RESOURCE_BOUND" do
    assert {:error, %Refusal{code: :REFUSED_RESOURCE_BOUND}} =
             call(Delta, :root_digest, [graph(5), [max: 2]])
  end

  test "Protocol.client_opts retains the caller :timeout for the worker deadline" do
    assert Keyword.get(Protocol.client_opts(timeout: 123), :timeout) == 123
  end

  test "Protocol.query_with worker deadline follows the caller :timeout" do
    blocker = fn _parsed, _endpoint, _opts ->
      receive do
        :never -> :ok
      end
    end

    started = System.monotonic_time(:millisecond)

    assert {:error, _} =
             Protocol.query_with(
               "http://127.0.0.1:1/sparql",
               "SELECT * WHERE { ?s ?p ?o }",
               [timeout: 200],
               blocker
             )

    assert System.monotonic_time(:millisecond) - started < 10_000
  end

  test "Local.query refuses over max_rows before returning rows to the caller" do
    assert {:error, %Refusal{code: :REFUSED_RESOURCE_BOUND}} =
             Local.query(graph(5), "SELECT * WHERE { ?s ?p ?o }", max_rows: 2)
  end
end
