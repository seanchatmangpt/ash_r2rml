# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.SparkFeaturesTest do
  use ExUnit.Case, async: true

  defmodule AuditFragment do
    use Spark.Dsl.Fragment,
      of: Ash.Resource,
      extensions: [AshR2RML.Resource]

    r2rml do
      property :name, "https://schema.org/name"
    end
  end

  defmodule FragmentResource do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource],
      fragments: [AuditFragment]

    attributes do
      uuid_primary_key :id
      attribute :name, :string, allow_nil?: false, public?: true
    end

    r2rml do
      table_name "fragment_resources"
      class "https://schema.org/FragmentThing"

      subject do
        template "https://example.org/fragment/{id}"
      end
    end
  end

  test "composes R2RML mappings using Spark.Dsl.Fragment" do
    {:ok, mapping} = AshR2RML.mapping_result(FragmentResource)
    assert mapping.ash_resource == FragmentResource
    assert mapping.class_iris == ["https://schema.org/FragmentThing"]

    [prop] = mapping.predicate_object_maps
    assert prop.attribute == :name
    assert prop.predicate_iri == "https://schema.org/name"
  end
end
