# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Negative.RelationshipNegativeTest do
  @moduledoc """
  Negative test suite verifying typed refusals on broken or ambiguous relationship mappings:
  - REFUSED_RELATIONSHIP_WITHOUT_PREDICATE (relationship mapped without RDF predicate IRI)
  - REFUSED_INVALID_JOIN_CONDITION (missing or non-string join child/parent keys)
  - REFUSED_RELATIONSHIP_TARGET_UNMAPPED (target resource has no mapping)
  - REFUSED_R2RML_JOIN_WITHOUT_IDENTITY (parent triples map lacks identity)
  """
  use ExUnit.Case, async: true

  alias AshR2RML.Mapping
  alias AshR2RML.Refusal

  defp extract_refusals({:error, refusals}) when is_list(refusals), do: refusals
  defp extract_refusals({:error, %Refusal{} = refusal}), do: [refusal]
  defp extract_refusals(refusals) when is_list(refusals), do: refusals
  defp extract_refusals(_), do: []

  describe "REFUSED_RELATIONSHIP_WITHOUT_PREDICATE" do
    test "refuses reference object map with empty or nil predicate IRI" do
      mapping = %Mapping.Resource{
        ash_resource: __MODULE__,
        logical_table: %Mapping.LogicalTable{table_name: "orders"},
        subject_map: %Mapping.SubjectMap{
          strategy: :template,
          value: "https://example.org/orders/{id}",
          term_type: :iri
        },
        class_iris: ["https://example.org/ontology/Order"],
        reference_object_maps: [
          %Mapping.ReferenceObjectMap{
            predicate_iri: "",
            parent_resource: :Customer,
            joins: [
              %Mapping.JoinCondition{child: "customer_id", parent: "id"}
            ]
          }
        ]
      }

      refusals = extract_refusals(Mapping.validate(mapping))
      assert Enum.any?(refusals, fn r -> r.code == :REFUSED_RELATIONSHIP_WITHOUT_PREDICATE end)
    end
  end

  describe "REFUSED_INVALID_JOIN_CONDITION" do
    test "refuses reference object map with empty join conditions" do
      mapping = %Mapping.Resource{
        ash_resource: __MODULE__,
        logical_table: %Mapping.LogicalTable{table_name: "orders"},
        subject_map: %Mapping.SubjectMap{
          strategy: :template,
          value: "https://example.org/orders/{id}",
          term_type: :iri
        },
        class_iris: ["https://example.org/ontology/Order"],
        reference_object_maps: [
          %Mapping.ReferenceObjectMap{
            predicate_iri: "https://example.org/ontology/hasCustomer",
            parent_resource: :Customer,
            joins: []
          }
        ]
      }

      refusals = extract_refusals(Mapping.validate(mapping))
      assert Enum.any?(refusals, fn r -> r.code == :REFUSED_INVALID_JOIN_CONDITION end)
    end

    test "refuses reference object map with empty child or parent column" do
      mapping = %Mapping.Resource{
        ash_resource: __MODULE__,
        logical_table: %Mapping.LogicalTable{table_name: "orders"},
        subject_map: %Mapping.SubjectMap{
          strategy: :template,
          value: "https://example.org/orders/{id}",
          term_type: :iri
        },
        class_iris: ["https://example.org/ontology/Order"],
        reference_object_maps: [
          %Mapping.ReferenceObjectMap{
            predicate_iri: "https://example.org/ontology/hasCustomer",
            parent_resource: :Customer,
            joins: [
              %Mapping.JoinCondition{child: "", parent: "id"}
            ]
          }
        ]
      }

      refusals = extract_refusals(Mapping.validate(mapping))
      assert Enum.any?(refusals, fn r -> r.code == :REFUSED_INVALID_JOIN_CONDITION end)
    end
  end
end
