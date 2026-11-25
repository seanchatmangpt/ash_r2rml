# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW11DeltaLensTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Mapping.Changeset
  alias AshR2RML.Refusal

  test "a struct passed as options is refused, not read as an empty option map" do
    graph = RDF.Graph.new({RDF.iri("http://schema.org/Person"), RDF.type(), RDF.iri("http://schema.org/Thing")})

    assert {:error, %Refusal{}} = Changeset.new(graph)
  end

  test "a plain map of options still builds" do
    assert {:ok, %Changeset{add: nil}} = Changeset.new(%{})
  end
end
