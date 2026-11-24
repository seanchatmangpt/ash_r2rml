# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.SubjectBlankNodePolicyTest do
  @moduledoc """
  Wire-level blank-node refusal: `Subject.iri_only?/1` and `Subject.check_iri_only/1`
  over real normalized mappings and a real unmapped ETS Ash resource.
  """
  use ExUnit.Case, async: true

  alias AshR2RML.Mapping.{
    LogicalTable,
    ObjectMap,
    PredicateObjectMap,
    ReferenceObjectMap,
    Resource,
    SubjectMap
  }

  alias AshR2RML.{Refusal, Subject}

  defmodule Dom do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.SubjectBlankNodePolicyTest.Unmapped
    end
  end

  defmodule Unmapped do
    use Ash.Resource, domain: AshR2RML.SubjectBlankNodePolicyTest.Dom, data_layer: Ash.DataLayer.Ets

    ets do
      private? true
    end

    actions do
      defaults [:read]
    end

    attributes do
      uuid_primary_key :id
    end
  end

  @ex "http://ex.org/"

  defp mapping(subject_map, extra \\ []) do
    struct!(
      %Resource{
        ash_resource: "Person",
        logical_table: %LogicalTable{table_name: "people"},
        subject_map: subject_map,
        class_iris: [@ex <> "Person"]
      },
      extra
    )
  end

  defp template, do: %SubjectMap{strategy: :template, value: @ex <> "p/{id}"}

  defp pom(term_type) do
    %PredicateObjectMap{
      attribute: :name,
      predicate_iri: @ex <> "name",
      object_map: %ObjectMap{strategy: :column, value: "name", term_type: term_type}
    }
  end

  test "IRI template subject with literal and IRI objects is ok" do
    m = mapping(template(), predicate_object_maps: [pom(:literal), pom(:iri)])
    assert Subject.check_iri_only(m) == :ok
    assert Subject.iri_only?(m)
  end

  test "column and constant IRI subjects are ok" do
    assert Subject.iri_only?(mapping(%SubjectMap{strategy: :column, value: "id"}))
    assert Subject.iri_only?(mapping(%SubjectMap{strategy: :constant, value: @ex <> "s"}))
  end

  test "blank-node subject is refused" do
    m = mapping(%SubjectMap{strategy: :blank_node, value: "id", term_type: :blank_node})
    refute Subject.iri_only?(m)

    assert {:error, %Refusal{code: :UNSUPPORTED_TERM_TYPE, subject: "Person"}} =
             Subject.check_iri_only(m)
  end

  test "blank-node object term type is refused" do
    m = mapping(template(), predicate_object_maps: [pom(:literal), pom(:blank_node)])
    refute Subject.iri_only?(m)

    assert {:error, %Refusal{code: :UNSUPPORTED_TERM_TYPE, evidence: %{predicate_iri: p}}} =
             Subject.check_iri_only(m)

    assert p == @ex <> "name"
  end

  test "reference object maps (IRI-only by construction) are ok" do
    rom = %ReferenceObjectMap{predicate_iri: @ex <> "knows", parent_resource: "Person"}
    assert Subject.iri_only?(mapping(template(), reference_object_maps: [rom]))
  end

  test "unmapped resource returns the same refusal as to_iri" do
    assert {:error, %Refusal{} = from_to_iri} = Subject.to_iri(Unmapped, id: "1")
    assert {:error, %Refusal{} = from_policy} = Subject.check_iri_only(Unmapped)
    assert from_policy == from_to_iri
    refute Subject.iri_only?(Unmapped)
  end
end
