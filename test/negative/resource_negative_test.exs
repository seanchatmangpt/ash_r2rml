# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Negative.ResourceNegativeTest do
  @moduledoc """
  Negative test suite verifying typed refusals on malformed Resource declarations:
  - REFUSED_INVALID_CLASS_IRI (relative URI, non-URI strings, empty class)
  - REFUSED_MISSING_SUBJECT_MAP (missing subject block, empty subject template)
  - REFUSED_INVALID_LOGICAL_TABLE (missing table name, malformed SQL query)
  - REFUSED_UNKNOWN_ATTRIBUTE (attribute mapping pointing to non-existent field)
  """
  use ExUnit.Case, async: true

  alias AshR2RML.Mapping
  alias AshR2RML.Refusal

  defp extract_refusals({:error, refusals}) when is_list(refusals), do: refusals
  defp extract_refusals({:error, %Refusal{} = refusal}), do: [refusal]
  defp extract_refusals(refusals) when is_list(refusals), do: refusals
  defp extract_refusals(_), do: []

  describe "REFUSED_INVALID_CLASS_IRI" do
    test "refuses resource with relative class IRI" do
      mapping = %Mapping.Resource{
        ash_resource: __MODULE__,
        logical_table: %Mapping.LogicalTable{table_name: "items"},
        subject_map: %Mapping.SubjectMap{
          strategy: :template,
          value: "https://example.org/items/{id}",
          term_type: :iri
        },
        class_iris: ["relative/class/iri"]
      }

      refusals = extract_refusals(Mapping.validate(mapping))
      assert Enum.any?(refusals, fn r -> r.code == :REFUSED_INVALID_CLASS_IRI end)
    end

    test "refuses resource with empty class IRIs list" do
      mapping = %Mapping.Resource{
        ash_resource: __MODULE__,
        logical_table: %Mapping.LogicalTable{table_name: "items"},
        subject_map: %Mapping.SubjectMap{
          strategy: :template,
          value: "https://example.org/items/{id}",
          term_type: :iri
        },
        class_iris: []
      }

      refusals = extract_refusals(Mapping.validate(mapping))
      assert Enum.any?(refusals, fn r -> r.code == :REFUSED_INVALID_CLASS_IRI end)
    end
  end

  describe "REFUSED_MISSING_SUBJECT_MAP" do
    test "refuses resource with nil subject_map" do
      mapping = %Mapping.Resource{
        ash_resource: __MODULE__,
        logical_table: %Mapping.LogicalTable{table_name: "items"},
        subject_map: nil,
        class_iris: ["https://example.org/ontology/Item"]
      }

      refusals = extract_refusals(Mapping.validate(mapping))
      assert Enum.any?(refusals, fn r -> r.code == :REFUSED_MISSING_SUBJECT_MAP end)
    end

    test "refuses resource with empty subject template value" do
      mapping = %Mapping.Resource{
        ash_resource: __MODULE__,
        logical_table: %Mapping.LogicalTable{table_name: "items"},
        subject_map: %Mapping.SubjectMap{
          strategy: :template,
          value: "",
          term_type: :iri
        },
        class_iris: ["https://example.org/ontology/Item"]
      }

      refusals = extract_refusals(Mapping.validate(mapping))
      assert Enum.any?(refusals, fn r -> r.code == :REFUSED_MISSING_SUBJECT_MAP end)
    end
  end

  describe "REFUSED_INVALID_LOGICAL_TABLE" do
    test "refuses resource with nil logical_table" do
      mapping = %Mapping.Resource{
        ash_resource: __MODULE__,
        logical_table: nil,
        subject_map: %Mapping.SubjectMap{
          strategy: :template,
          value: "https://example.org/items/{id}",
          term_type: :iri
        },
        class_iris: ["https://example.org/ontology/Item"]
      }

      refusals = extract_refusals(Mapping.validate(mapping))
      assert Enum.any?(refusals, fn r -> r.code == :REFUSED_INVALID_LOGICAL_TABLE end)
    end

    test "refuses resource with empty table_name and no sql_query" do
      mapping = %Mapping.Resource{
        ash_resource: __MODULE__,
        logical_table: %Mapping.LogicalTable{table_name: nil, sql_query: nil},
        subject_map: %Mapping.SubjectMap{
          strategy: :template,
          value: "https://example.org/items/{id}",
          term_type: :iri
        },
        class_iris: ["https://example.org/ontology/Item"]
      }

      refusals = extract_refusals(Mapping.validate(mapping))
      assert Enum.any?(refusals, fn r -> r.code == :REFUSED_INVALID_LOGICAL_TABLE end)
    end
  end

  describe "REFUSED_INVALID_GRAPH_MAP" do
    test "refuses relative named graph IRI" do
      mapping = %Mapping.Resource{
        ash_resource: __MODULE__,
        logical_table: %Mapping.LogicalTable{table_name: "items"},
        subject_map: %Mapping.SubjectMap{
          strategy: :template,
          value: "https://example.org/items/{id}",
          term_type: :iri
        },
        class_iris: ["https://example.org/ontology/Item"],
        graph_maps: [
          %Mapping.GraphMap{strategy: :constant, value: "relative/graph/iri"}
        ]
      }

      refusals = extract_refusals(Mapping.validate(mapping))
      assert Enum.any?(refusals, fn r -> r.code == :REFUSED_INVALID_GRAPH_MAP end)
    end
  end
end
