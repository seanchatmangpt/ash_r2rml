# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.SecuritySensitiveCompilePathTest do
  @moduledoc """
  `sensitive?: true` attributes mapped through the r2rml DSL never survive
  `Compiler.compile/1` and never reach rendered R2RML Turtle.
  """
  use ExUnit.Case, async: false

  @secret_iri "http://schema.org/taxID"
  @name_iri "http://xmlns.com/foaf/0.1/name"

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.SecuritySensitiveCompilePathTest.Person
    end
  end

  defmodule Person do
    use Ash.Resource,
      domain: AshR2RML.SecuritySensitiveCompilePathTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    r2rml do
      table_name("sensitive_people")
      class("http://xmlns.com/foaf/0.1/Person")
      subject(template: "urn:uuid:{id}")
      property(:name, "http://xmlns.com/foaf/0.1/name")
      property(:ssn, "http://schema.org/taxID")
    end

    actions do
      defaults [:read, :destroy]

      create :create do
        primary? true
        accept [:name, :ssn]
      end
    end

    attributes do
      uuid_primary_key :id
      attribute :name, :string, allow_nil?: false, public?: true
      attribute :ssn, :string, public?: true, sensitive?: true
    end
  end

  defp person_mapping do
    assert {:ok, bundle} = AshR2RML.Compiler.compile([Person])
    Enum.find(bundle.resources, &(&1.ash_resource == Person)) || flunk("Person mapping missing")
  end

  test "compiled mapping has no predicate map for the sensitive attribute" do
    mapping = person_mapping()
    attrs = Enum.map(mapping.predicate_object_maps, & &1.attribute)
    iris = Enum.map(mapping.predicate_object_maps, & &1.predicate_iri)

    refute :ssn in attrs
    refute @secret_iri in iris
  end

  test "metadata records the excluded sensitive attribute" do
    mapping = person_mapping()
    assert :ssn in Map.get(mapping.metadata, :sensitive_excluded_attributes, [])
  end

  test "non-sensitive attribute remains mapped" do
    mapping = person_mapping()
    assert :name in Enum.map(mapping.predicate_object_maps, & &1.attribute)
    assert @name_iri in Enum.map(mapping.predicate_object_maps, & &1.predicate_iri)
    refute :name in Map.get(mapping.metadata, :sensitive_excluded_attributes, [])
  end

  test "rendered Turtle never contains the sensitive predicate IRI" do
    assert {:ok, bundle} = AshR2RML.Compiler.compile([Person])
    assert {:ok, ttl} = AshR2RML.R2RML.render(bundle)

    refute ttl =~ @secret_iri
    assert ttl =~ "rr:predicate <#{@name_iri}>"
  end
end
