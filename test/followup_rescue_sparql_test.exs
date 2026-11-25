# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.FollowupRescueSparqlTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Refusal

  test "normalize refuses an unsupported result shape and names the exception class" do
    assert {:error, %Refusal{code: :REFUSED_UNPROVEN_EQUIVALENCE} = refusal} =
             AshR2RML.SPARQL.Result.normalize(:not_rdf_data)

    assert is_binary(inspect(refusal))
    assert inspect(refusal) =~ "exception"
  end

  test "admit refuses invalid query text with a typed refusal" do
    assert {:error, %Refusal{code: :REFUSED_UNPROVEN_EQUIVALENCE}} =
             AshR2RML.SPARQL.Query.admit("SELEC nonsense {")
  end

  test "admit refuses non-query input" do
    assert {:error, %Refusal{code: :REFUSED_UNPROVEN_EQUIVALENCE}} = AshR2RML.SPARQL.Query.admit(42)
  end

  test "admit accepts a valid query and keeps its identity" do
    q = "SELECT ?s WHERE { ?s <http://schema.org/name> ?o }"
    assert {:ok, admitted} = AshR2RML.SPARQL.Query.admit(q)
    assert admitted.form == :select
    assert admitted.source == q
  end
end
