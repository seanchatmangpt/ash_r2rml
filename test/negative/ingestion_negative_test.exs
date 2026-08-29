# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Negative.IngestionNegativeTest do
  @moduledoc """
  Negative test suite verifying typed refusals on malformed RDF/Turtle and SHACL inputs:
  - REFUSED_RDF_PARSE on syntax errors
  - REFUSED_SHACL_PROFILE_INCOMPLETE when NodeShapes lack required operational targets
  """
  use ExUnit.Case, async: true

  alias AshR2RML.Ingestion

  describe "RDF / Turtle Ingestion Negative Tests" do
    test "refuses malformed Turtle syntax with parse refusal" do
      malformed_turtle = """
      @prefix ex: <https://example.com/> .
      ex:BadResource a ex:Something
      # Missing trailing dot and syntax error
      ex:NextResource ex:broken
      """

      assert {:error, [refusal | _]} = Ingestion.from_turtle(malformed_turtle)
      assert refusal.code == :REFUSED_RDF_PARSE
    end

    test "refuses Turtle with no SHACL NodeShapes" do
      plain_rdf = """
      @prefix ex: <https://example.com/> .
      @prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .

      ex:SomeClass a rdfs:Class ;
          rdfs:label "Some Class without SHACL closure" .
      """

      assert {:error, [refusal | _]} = Ingestion.from_turtle(plain_rdf)
      assert refusal.code == :REFUSED_SHACL_PROFILE_INCOMPLETE
    end

    test "refuses NodeShape missing targetClass or targetNode" do
      incomplete_shape = """
      @prefix sh: <http://www.w3.org/ns/shacl#> .
      @prefix ex: <https://example.com/> .

      ex:OrphanShape a sh:NodeShape ;
          sh:property [
              sh:path ex:someProp ;
              sh:datatype <http://www.w3.org/2001/XMLSchema#string>
          ] .
      """

      assert {:error, [refusal | _]} = Ingestion.from_turtle(incomplete_shape)

      assert refusal.code in [
               :REFUSED_SHACL_PROFILE_INCOMPLETE,
               :REFUSED_UNMAPPED_RESOURCE_CLASS,
               :REFUSED_INVALID_CLASS_IRI
             ]
    end
  end
end
