# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.NQuadsTest do
  use ExUnit.Case, async: true

  alias AshR2RML.NQuads
  alias AshR2RML.Refusal

  doctest AshR2RML.NQuads

  defp iri(s), do: {:iri, "https://schema.org/" <> s}

  defp sample do
    [
      {iri("a"), iri("p"), {:literal, "x"}, nil},
      {iri("b"), iri("p"), {:literal, "7", {:datatype, "https://schema.org/int"}}, iri("g1")},
      {iri("c"), iri("q"), {:literal, "hi", {:lang, "en"}}, iri("g2")},
      {iri("a"), iri("q"), iri("b"), nil},
      {iri("z"), iri("p"), {:literal, "line\nbreak"}, iri("g1")},
      {iri("m"), iri("p"), {:literal, "a\"b\\c\r"}, nil}
    ]
  end

  test "output is invariant under 60 shuffles" do
    {:ok, expected} = NQuads.serialize(sample())

    for _ <- 1..60 do
      assert {:ok, ^expected} = NQuads.serialize(Enum.shuffle(sample()))
    end
  end

  test "lines are sorted and newline terminated" do
    {:ok, out} = NQuads.serialize(sample())
    assert String.ends_with?(out, "\n")
    ls = String.split(out, "\n", trim: true)
    assert ls == Enum.sort(ls)
  end

  test "literal escaping" do
    {:ok, out} = NQuads.serialize([{iri("s"), iri("p"), {:literal, "a\"b\\c\nd\re"}, nil}])
    assert out == ~s(<https://schema.org/s> <https://schema.org/p> "a\\"b\\\\c\\nd\\re" .\n)
  end

  test "iri escaping of forbidden characters" do
    {:ok, out} = NQuads.serialize([{{:iri, "https://schema.org/a b<c>"}, iri("p"), {:literal, "x"}, nil}])
    assert out =~ "<https://schema.org/a\\u0020b\\u003Cc\\u003E>"
  end

  test "datatype, lang lowercasing, xsd:string elision" do
    xs = "http://www.w3.org/2001/XMLSchema#string"

    {:ok, out} =
      NQuads.serialize([
        {iri("s"), iri("p"), {:literal, "v", {:datatype, xs}}, nil},
        {iri("s"), iri("q"), {:literal, "v", {:lang, "EN-US"}}, nil},
        {iri("s"), iri("r"), {:literal, "1", {:datatype, "https://schema.org/int"}}, nil}
      ])

    assert out =~ ~s(<https://schema.org/p> "v" .)
    assert out =~ ~s("v"@en-us .)
    assert out =~ ~s("1"^^<https://schema.org/int> .)
  end

  test "duplicates collapse" do
    q = {iri("s"), iri("p"), {:literal, "x"}, nil}
    {:ok, out} = NQuads.serialize([q, q, q])
    assert String.split(out, "\n", trim: true) |> length() == 1
  end

  test "default graph omits label, named graph emits it" do
    {:ok, out} =
      NQuads.serialize([
        {iri("s"), iri("p"), {:literal, "x"}, nil},
        {iri("s"), iri("p"), {:literal, "x"}, iri("g")}
      ])

    assert out ==
             ~s(<https://schema.org/s> <https://schema.org/p> "x" .\n) <>
               ~s(<https://schema.org/s> <https://schema.org/p> "x" <https://schema.org/g> .\n)
  end

  test "empty input yields empty output" do
    assert {:ok, ""} = NQuads.serialize([])
  end

  test "blank nodes in any position are refused" do
    b = {:bnode, "b0"}
    ok = {:literal, "x"}

    for q <- [
          {b, iri("p"), ok, nil},
          {iri("s"), iri("p"), b, nil},
          {iri("s"), iri("p"), ok, b},
          {iri("s"), b, ok, nil}
        ] do
      assert {:error, %Refusal{code: :REFUSED_INVALID_TERM_MAP, evidence: %{reason: :blank_node}}} =
               NQuads.serialize([q])
    end
  end

  test "invalid terms are refused" do
    assert {:error, %Refusal{evidence: %{reason: :invalid_term}}} =
             NQuads.serialize([{{:literal, "x"}, iri("p"), {:literal, "y"}, nil}])

    assert {:error, %Refusal{evidence: %{reason: :invalid_term}}} = NQuads.serialize([:nope])
  end

  test "invalid UTF-8 in an IRI is a typed refusal, not a raise" do
    bad = {:iri, <<"https://schema.org/", 0xFF, 0xFE>>}

    assert {:error, %Refusal{code: :REFUSED_INVALID_TERM_MAP, evidence: %{reason: :invalid_term}}} =
             NQuads.serialize([{bad, iri("p"), {:literal, "x"}, nil}])
  end
end
