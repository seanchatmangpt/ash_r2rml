# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.ResultDigestVectorTest do
  use ExUnit.Case, async: true

  alias AshR2RML.OBDA.Result

  # Documented framing recomputed with raw :crypto, independent of Result.digest/3.
  defp reference(ttl, sparql, rows) do
    canonical = :erlang.term_to_binary(rows, [:deterministic])

    state =
      Enum.reduce([ttl, sparql, canonical], :crypto.hash_init(:sha256), fn part, acc ->
        acc
        |> :crypto.hash_update(<<byte_size(part)::unsigned-big-64>>)
        |> :crypto.hash_update(part)
      end)

    state |> :crypto.hash_final() |> Base.encode16(case: :lower)
  end

  test "digest equals the documented frame concatenation hashed with raw crypto" do
    rows = [%{"x" => 1, "y" => "a"}, %{"x" => 2}]
    ttl = "@prefix rr: <http://www.w3.org/ns/r2rml#> ."
    sparql = "SELECT * WHERE { ?s ?p ?o }"

    assert Result.digest(ttl, sparql, rows) == reference(ttl, sparql, rows)
  end

  test "digest equals a single hash over the flat framed binary" do
    rows = [%{"x" => "é"}]
    ttl = "ttl é"
    sparql = "ASK {}"
    canonical = :erlang.term_to_binary(rows, [:deterministic])

    flat =
      for part <- [ttl, sparql, canonical], into: <<>> do
        <<byte_size(part)::unsigned-big-64, part::binary>>
      end

    expected = :sha256 |> :crypto.hash(flat) |> Base.encode16(case: :lower)
    assert Result.digest(ttl, sparql, rows) == expected
  end

  test "empty inputs have a stable vector" do
    assert Result.digest("", "", []) == reference("", "", [])
    assert String.length(Result.digest("", "", [])) == 64
  end

  test "length prefixes make the framing injective across field boundaries" do
    refute Result.digest("ab", "c", []) == Result.digest("a", "bc", [])
  end
end
