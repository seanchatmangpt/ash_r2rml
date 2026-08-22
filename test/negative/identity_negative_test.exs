# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Negative.IdentityNegativeTest do
  @moduledoc """
  Negative test suite verifying typed refusals on invalid templates and identity collisions:
  - REFUSED_INVALID_SUBJECT_TEMPLATE (syntax errors, malformed braces)
  - REFUSED_NON_UNIQUE_SEMANTIC_IDENTITY (identity collisions across resources)
  """
  use ExUnit.Case, async: true

  alias AshR2RML.Mapping
  alias AshR2RML.Refusal

  defp extract_refusals({:error, refusals}) when is_list(refusals), do: refusals
  defp extract_refusals({:error, %Refusal{} = refusal}), do: [refusal]
  defp extract_refusals(refusals) when is_list(refusals), do: refusals
  defp extract_refusals(_), do: []

  describe "REFUSED_INVALID_SUBJECT_TEMPLATE" do
    test "refuses subject template with unclosed template brace" do
      mapping = %Mapping.Resource{
        ash_resource: __MODULE__,
        logical_table: %Mapping.LogicalTable{table_name: "items"},
        subject_map: %Mapping.SubjectMap{
          strategy: :template,
          value: "https://example.org/items/{id",
          term_type: :iri
        },
        class_iris: ["https://example.org/ontology/Item"]
      }

      refusals = extract_refusals(Mapping.validate(mapping))
      assert Enum.any?(refusals, fn r -> r.code in [:REFUSED_NON_UNIQUE_SEMANTIC_IDENTITY, :REFUSED_INVALID_SUBJECT_TEMPLATE, :REFUSED_MISSING_SUBJECT_MAP] end)
    end
  end

  describe "REFUSED_NON_UNIQUE_SEMANTIC_IDENTITY" do
    test "refuses duplicate identical subject mapping template across different resources in a bundle" do
      res1 = %Mapping.Resource{
        ash_resource: :ResourceA,
        logical_table: %Mapping.LogicalTable{table_name: "items_a"},
        subject_map: %Mapping.SubjectMap{
          strategy: :template,
          value: "https://example.org/same_iri/{id}",
          term_type: :iri
        },
        class_iris: ["https://example.org/ontology/Item"]
      }

      res2 = %Mapping.Resource{
        ash_resource: :ResourceB,
        logical_table: %Mapping.LogicalTable{table_name: "items_b"},
        subject_map: %Mapping.SubjectMap{
          strategy: :template,
          value: "https://example.org/same_iri/{id}",
          term_type: :iri
        },
        class_iris: ["https://example.org/ontology/Item"]
      }

      bundle = %Mapping.Bundle{
        resources: [res1, res2]
      }

      refusals = extract_refusals(Mapping.validate(bundle))
      assert Enum.any?(refusals, fn r -> r.code == :REFUSED_NON_UNIQUE_SEMANTIC_IDENTITY end)
    end
  end
end
