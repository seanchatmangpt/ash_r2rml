# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RedTermsIntrospectionTest do
  @moduledoc """
  Red-before-green courts for Terms.valid_iri?/1 (H33) and
  Introspection.destination_column/2 (H36).
  """
  use ExUnit.Case, async: false

  alias AshR2RML.GrandExample.Organization
  alias AshR2RML.Introspection
  alias AshR2RML.Mapping.{Bundle, LogicalTable, Resource, SubjectMap}
  alias AshR2RML.R2RML.Terms
  alias AshR2RML.Refusal

  defp hand_resource(class_iris) do
    %Resource{
      ash_resource: "urn:uuid:00000000-0000-0000-0000-00000000000a",
      logical_table: %LogicalTable{table_name: "a"},
      subject_map: %SubjectMap{strategy: :template, value: "urn:uuid:{id}"},
      class_iris: class_iris,
      identities: [[:id]],
      metadata: %{attribute_columns: %{id: "id"}}
    }
  end

  defp validate(class_iris), do: Terms.validate(%Bundle{resources: [hand_resource(class_iris)]})

  test "H33 control: a well-formed class IRI is admitted" do
    assert :ok = validate(["http://schema.org/Person"])
  end

  test "H33 empty IRI is refused" do
    assert {:error, %Refusal{}} = validate([""])
  end

  test "H33 invalid UTF-8 IRI is refused" do
    assert {:error, %Refusal{}} = validate([<<"http://schema.org/", 0xFF>>])
  end

  test "H33 C1 control character in an IRI is refused" do
    assert {:error, %Refusal{}} = validate(["http://schema.org/a" <> <<0xC2, 0x85>> <> "b"])
    assert {:error, %Refusal{}} = validate(["http://schema.org/a" <> <<0xC2, 0x9F>>])
  end

  defp dsl_state(relationship) do
    attribute = struct!(Ash.Resource.Attribute, name: :org_id, type: Ash.Type.String)

    %{
      [:attributes] => %{entities: [attribute]},
      [:relationships] => %{entities: [relationship]}
    }
  end

  defp belongs_to(destination, destination_attribute) do
    struct!(Ash.Resource.Relationships.BelongsTo,
      name: :org,
      type: :belongs_to,
      source_attribute: :org_id,
      destination: destination,
      destination_attribute: destination_attribute
    )
  end

  defp relationship(destination, destination_attribute) do
    rel = belongs_to(destination, destination_attribute)
    Introspection.relationship(__MODULE__.Source, :org, dsl_state(rel))
  end

  test "H36 control: compiled destination with a real attribute yields its column" do
    assert {:ok, %{joins: [%{parent: "id"}]}} = relationship(Organization, :id)
  end

  test "H36 compiled destination with an unknown attribute is refused" do
    assert {:error, %Refusal{}} = relationship(Organization, :no_such_attribute_xyz)
  end

  test "H36 nil destination attribute is refused, not fabricated as an empty column" do
    assert {:error, %Refusal{}} = relationship(Organization, nil)
  end

  test "H36 a destination that is not an Ash resource is refused, not given a fabricated column" do
    assert {:error, %Refusal{}} = relationship(String, :name)
  end

  # FIXTURE-DEFECT correction: resources that reference each other compile in one pass, so an
  # uncompiled destination must keep its declared attribute name; the dependency-closed bundle
  # refuses a target that never materializes (REFUSED_RELATIONSHIP_TARGET_UNMAPPED).
  test "H36 an uncompiled destination keeps the declared attribute name, not a guessed column" do
    assert {:ok, %{joins: [%{parent: "owner_ref"}]}} =
             relationship(Module.concat(__MODULE__, NoSuchDestination), :owner_ref)
  end
end
