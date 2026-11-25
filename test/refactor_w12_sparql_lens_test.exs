# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW12SparqlLensTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Refusal
  alias AshR2RML.SPARQL.Protocol

  @endpoint "http://schema.org/sparql"
  @query "SELECT * WHERE { ?s ?p ?o }"

  for bad <- [:infinity, 0, -5, nil, "30"] do
    test "timeout #{inspect(bad)} is refused before any network use" do
      assert {:error, %Refusal{code: :REFUSED_INVALID_FEDERATION_ENVIRONMENT} = refusal} =
               Protocol.query(@endpoint, @query, timeout: unquote(bad))

      assert refusal.evidence.timeout == inspect(unquote(bad))
    end
  end
end
