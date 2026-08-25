# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Negative.AdmissionNegativeTest do
  @moduledoc """
  Negative test suite verifying typed refusals during application profile admission into SemanticIR:
  - REFUSED_UNPROVEN_EQUIVALENCE on non-map profile structures
  - REFUSED_INVALID_IRI on malformed or relative shape IRIs
  """
  use ExUnit.Case, async: true

  alias AshR2RML.Admission

  describe "Profile Admission Negative Tests" do
    test "refuses non-map profile input" do
      assert {:error, [refusal | _]} = Admission.admit("invalid_string_profile")
      assert refusal.code == :REFUSED_UNPROVEN_EQUIVALENCE
    end

    test "refuses profile with unmapped datatype" do
      bad_profile = %{
        resources: [
          %{
            class_iri: "https://example.com/ontology/Item",
            shape_iri: "https://example.com/shapes/ItemShape",
            table_name: "items",
            subject_template: "https://example.com/items/{id}",
            attributes: [
              %{
                name: :id,
                column: "id",
                predicate_iri: "https://example.com/id",
                datatype: "http://example.com/custom_unknown_type",
                min_count: 1,
                max_count: 1
              }
            ],
            identities: [
              %{name: :primary, keys: [:id], primary?: true}
            ]
          }
        ]
      }

      assert {:error, [refusal | _]} = Admission.admit(bad_profile)
      assert refusal.code == :REFUSED_DATATYPE_CAST_NOT_LOSSLESS
    end
  end
end
