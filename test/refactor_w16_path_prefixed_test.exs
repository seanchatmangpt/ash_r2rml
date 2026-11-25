# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW16PathPrefixedTest do
  use ExUnit.Case, async: true

  alias AshR2RML.OBDA
  alias AshR2RML.Refusal

  @prefix "PREFIX ex: <http://schema.org/> "

  for {name, body} <- [
        {"one-or-more", "?s ex:p+ ?o"},
        {"zero-or-more", "?s ex:p* ?o"},
        {"zero-or-one", "?s ex:p? ?o"},
        {"inverse", "?s ^ex:p ?o"},
        {"parenthesized sequence", "?s (ex:a/ex:b) ?o"},
        {"alternative", "?s ex:a|ex:b ?o"},
        {"sequence", "?s ex:a/ex:b ?o"}
      ] do
    test "prefixed #{name} path is refused" do
      assert {:error, %Refusal{code: :REFUSED_UNSUPPORTED_SPARQL_FEATURE}} =
               OBDA.check_supported_shapes(@prefix <> "SELECT ?s WHERE { " <> unquote(body) <> " }")
    end
  end

  test "positive controls pass" do
    assert :ok = OBDA.check_supported_shapes(@prefix <> "SELECT ?s WHERE { ?s ex:name ?o . ?s ex:age ?a }")
    assert :ok = OBDA.check_supported_shapes(@prefix <> "SELECT ?x WHERE { ?x ex:age ?a FILTER(?a+1 > 2) }")
    assert :ok = OBDA.check_supported_shapes(@prefix <> "SELECT ?s WHERE { ?s a ex:Person }")
  end
end
