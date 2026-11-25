# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW11UnsupportedShapesTest do
  use ExUnit.Case, async: true

  alias AshR2RML.{OBDA, Refusal}

  @s "http://schema.org/"

  for {name, sparql} <- [
        {"VALUES", ~s(SELECT ?n WHERE { VALUES ?n { "a" } ?s <#{@s}name> ?n })},
        {"sub-SELECT", "SELECT ?n WHERE { { SELECT ?s WHERE { ?s <#{@s}age> ?a } } ?s <#{@s}name> ?n }"},
        {"property path sequence", "SELECT ?o WHERE { ?s <#{@s}a>/<#{@s}b> ?o }"},
        {"property path alternative", "SELECT ?o WHERE { ?s <#{@s}a>|<#{@s}b> ?o }"},
        {"property path inverse", "SELECT ?o WHERE { ?s ^<#{@s}a> ?o }"}
      ] do
    test "#{name} is refused, never answered wrongly" do
      assert {:error, %Refusal{code: :REFUSED_UNSUPPORTED_SPARQL_FEATURE}} =
               OBDA.check_supported_shapes(unquote(sparql))
    end
  end

  test "plain BGP, FILTER and string literals containing the keywords pass" do
    assert :ok = OBDA.check_supported_shapes("SELECT ?n WHERE { ?s <#{@s}name> ?n FILTER(?n != \"VALUES\") }")
    assert :ok = OBDA.check_supported_shapes("SELECT ?s WHERE { ?s <#{@s}a/b> ?o }")
  end
end
