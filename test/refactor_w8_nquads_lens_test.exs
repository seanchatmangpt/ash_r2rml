# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW8NQuadsLensTest do
  use ExUnit.Case, async: true

  alias AshR2RML.NQuads

  defp quad(tag) do
    {{:iri, "http://schema.org/a"}, {:iri, "http://schema.org/name"}, {:literal, "x", {:lang, tag}}, nil}
  end

  test "language tags containing spaces or newlines are refused, not emitted" do
    for tag <- ["e n", "en\n", "en-", "-en", "", "e\"n"] do
      assert {:error, r} = NQuads.serialize([quad(tag)])
      assert r.evidence.reason == :invalid_term
    end
  end

  test "well-formed tags are lowercased" do
    assert {:ok, out} = NQuads.serialize([quad("en-GB")])
    assert out =~ "\"x\"@en-gb ."
  end
end
