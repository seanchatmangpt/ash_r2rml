# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.CompositeIdentityTest.Resource do
  use Ash.Resource,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML.Resource]

  attributes do
    attribute :tenant_id, :string, primary_key?: true, allow_nil?: false, source: :tenant_key
    attribute :external_id, :string, primary_key?: true, allow_nil?: false, source: :external_key
    attribute :display_name, :string, allow_nil?: false, source: :display_label
  end

  r2rml do
    table_name("composite_people")
    class("https://schema.org/Person")

    subject do
      template("https://example.test/people/{tenant_key}/{external_key}")
    end

    property(:display_name, "https://schema.org/name")
  end
end

defmodule AshR2RML.CompositeIdentityTest do
  use ExUnit.Case, async: true

  alias AshR2RML.CompositeIdentityTest.Resource

  test "compiled composite identity is translated through Ash source columns" do
    assert AshR2RML.Introspection.identities(Resource) == [[:external_id, :tenant_id]]
    assert AshR2RML.Introspection.identity_columns(Resource) == [["external_key", "tenant_key"]]

    mapping = AshR2RML.Resource.Info.mapping!(Resource)
    assert mapping.metadata.attribute_columns.tenant_id == "tenant_key"
    assert mapping.metadata.attribute_columns.external_id == "external_key"
    assert mapping.metadata.identity_columns == [["external_key", "tenant_key"]]
    assert AshR2RML.Mapping.stable_subject_identity?(mapping)
    assert :ok = AshR2RML.Mapping.validate(mapping)
  end

  test "unknown attribute storage is refused rather than guessed" do
    assert {:error, refusal} = AshR2RML.Introspection.column(Resource, :not_an_attribute)
    assert refusal.code == :REFUSED_UNKNOWN_ATTRIBUTE
  end
end

defmodule AshR2RML.LegacyAmbientMappingTest do
  use ExUnit.Case, async: true

  defmodule LegacyOnly do
    def __ash_r2rml_mapping__ do
      %AshR2RML.LegacyMapping{
        resource: __MODULE__,
        class_iri: "https://schema.org/Thing",
        subject_template: "https://example.test/{id}",
        logical_table: {:table, "things"}
      }
    end
  end

  test "legacy compatibility hooks cannot manufacture an ambient canonical mapping" do
    assert {:error, refusal} = AshR2RML.Resource.Info.mapping_result(LegacyOnly)
    assert refusal.code == :REFUSED_MISSING_SUBJECT_MAP
  end
end
