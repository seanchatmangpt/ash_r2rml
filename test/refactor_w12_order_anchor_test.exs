# SPDX-License-Identifier: Apache-2.0
defmodule AshR2RML.RefactorW12OrderAnchorTest do
  use ExUnit.Case, async: true

  alias AshR2RML.OBDA
  alias AshR2RML.Refusal

  @body "{ ?s <http://schema.org/name> ?a . ?s <http://schema.org/url> ?b }"

  test "a decoy SELECT inside a leading comment does not validate the real clause" do
    sparql = "# SELECT ?a ?b WHERE { }\nSELECT ?a WHERE #{@body} ORDER BY ?b"
    assert {:error, %Refusal{}} = OBDA.check_order_projected(sparql)
  end

  test "a decoy SELECT inside a string literal does not validate the real clause" do
    sparql =
      "SELECT ?a WHERE { ?s <http://schema.org/name> \"SELECT ?a ?b WHERE {\" . " <>
        "?s <http://schema.org/url> ?b } ORDER BY ?b"

    assert {:error, %Refusal{}} = OBDA.check_order_projected(sparql)
  end

  test "comment decoy before the real SELECT still admits a projected ORDER BY variable" do
    sparql = "# SELECT ?z WHERE { }\nSELECT ?a ?b WHERE #{@body} ORDER BY ?b"
    assert :ok = OBDA.check_order_projected(sparql)
  end
end
