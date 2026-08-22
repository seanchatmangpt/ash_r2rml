# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Negative.DatatypeNegativeTest do
  @moduledoc """
  Negative test suite verifying typed refusals on unmapped or invalid datatypes:
  - UNSUPPORTED_ASH_TYPE (unknown custom type attempting to resolve)
  - REFUSED_UNMAPPED_DATATYPE (predicate object map with missing datatype mapping)
  - Proof that unknown types NEVER silently degrade to xsd:string
  """
  use ExUnit.Case, async: true

  alias AshR2RML.Datatype.Registry
  alias AshR2RML.Mapping
  alias AshR2RML.Refusal

  defmodule UnknownType do
    # Arbitrary module that does NOT implement Ash.Type or AshR2RML.Type
  end

  defp extract_refusals({:error, refusals}) when is_list(refusals), do: refusals
  defp extract_refusals({:error, %Refusal{} = refusal}), do: [refusal]
  defp extract_refusals(refusals) when is_list(refusals), do: refusals
  defp extract_refusals(_), do: []

  describe "UNSUPPORTED_ASH_TYPE" do
    test "refuses to resolve an unknown custom struct type" do
      assert {:error, %Refusal{code: :UNSUPPORTED_ASH_TYPE} = refusal} = Registry.resolve(UnknownType)
      assert refusal.detail =~ "Ash type has no admitted RDF datatype contract"
    end

    test "refuses to resolve an unregistered atom type" do
      assert {:error, %Refusal{code: :UNSUPPORTED_ASH_TYPE}} = Registry.resolve(:completely_unknown_type)
    end
  end

  describe "REFUSED_UNMAPPED_DATATYPE" do
    test "refuses predicate object map with nil or invalid datatype resolution" do
      mapping = %Mapping.Resource{
        ash_resource: __MODULE__,
        logical_table: %Mapping.LogicalTable{table_name: "items"},
        subject_map: %Mapping.SubjectMap{
          strategy: :template,
          value: "https://example.org/items/{id}",
          term_type: :iri
        },
        class_iris: ["https://example.org/ontology/Item"],
        predicate_object_maps: [
          %Mapping.PredicateObjectMap{
            predicate_iri: "https://example.org/ontology/unmappedProp",
            object_map: %Mapping.ObjectMap{
              strategy: :column,
              value: "raw_payload",
              term_type: :literal,
              datatype: %Mapping.Datatype{rdf_datatype: "relative/datatype"}
            }
          }
        ]
      }

      refusals = extract_refusals(Mapping.validate(mapping))
      assert Enum.any?(refusals, fn r -> r.code == :REFUSED_UNMAPPED_DATATYPE end)
    end
  end
end
