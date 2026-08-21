# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.AdvancedGraphFeaturesTest do
  use ExUnit.Case, async: true

  defmodule Organization do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :name, :string, allow_nil?: false, public?: true
    end

    r2rml do
      table_name("organizations")
      class(["https://schema.org/Organization", "https://schema.org/Corporation"])

      subject do
        template("https://example.org/organizations/{id}")
      end

      property(:name, "https://schema.org/name")
    end
  end

  defmodule Person do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :name, :string, allow_nil?: false, public?: true
    end

    relationships do
      belongs_to :organization, Organization, allow_nil?: false, public?: true
    end

    r2rml do
      table_name("people")
      class("https://schema.org/Person")

      subject do
        template("https://example.org/people/{id}")
      end

      property(:name, "https://schema.org/name")
      reference(:organization, "https://schema.org/memberOf", inverse_predicate: "https://schema.org/hasMember")
    end
  end

  test "supports multi-class RDF labeling on single subject map" do
    {:ok, mapping} = AshR2RML.mapping_result(Organization)
    assert Enum.sort(mapping.class_iris) == ["https://schema.org/Corporation", "https://schema.org/Organization"]

    {:ok, ttl} = AshR2RML.render_r2rml(Organization)
    assert ttl =~ "rr:class <https://schema.org/Organization>"
    assert ttl =~ "rr:class <https://schema.org/Corporation>"
  end

  test "supports inverse edge predicate generation in R2RML triples map" do
    {:ok, ttl} = AshR2RML.render_r2rml([Person, Organization])
    assert ttl =~ "rr:predicate <https://schema.org/hasMember>"
    assert ttl =~ "rr:parentTriplesMap <#AshR2RML_AdvancedGraphFeaturesTest_Person>"
  end
end
