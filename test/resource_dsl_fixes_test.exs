# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.ResourceDslFixesTest do
  @moduledoc """
  Real Ash resources pinning the DSL compile fixes: conflicting property options
  are refused (never silently resolved), and DSL-declared has_one/has_many joins
  come from the declared attributes, never from a guessed "<rel>_id" column.
  """
  use ExUnit.Case, async: true

  alias AshR2RML.Mapping.{ObjectMap, ReferenceObjectMap}
  alias AshR2RML.Resource.Info

  defmodule Kid do
    use Ash.Resource, domain: nil, data_layer: Ash.DataLayer.Ets, extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :owner_id, :uuid, public?: true
    end

    r2rml do
      table_name("fix_kids")
      class("http://xmlns.com/foaf/0.1/Person")

      subject template: "urn:uuid:{id}"
    end
  end

  defmodule Owner do
    use Ash.Resource, domain: nil, data_layer: Ash.DataLayer.Ets, extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
    end

    relationships do
      has_many :kids, AshR2RML.ResourceDslFixesTest.Kid, destination_attribute: :owner_id, public?: true
    end

    r2rml do
      table_name("fix_owners")
      class("http://www.w3.org/ns/org#Organization")

      subject template: "urn:uuid:{id}"

      reference(:kids, "http://www.w3.org/ns/org#hasMember")
    end
  end

  defmodule LangOnly do
    use Ash.Resource, domain: nil, data_layer: Ash.DataLayer.Ets, extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :title, :string, public?: true
    end

    r2rml do
      table_name("fix_lang")
      class("https://schema.org/Thing")

      subject template: "urn:uuid:{id}"

      property(:title, "http://purl.org/dc/terms/title", language: "en")
    end
  end

  # Compiles a one-attribute resource with the given property line; returns
  # {:ok, module} or {:error, message}.
  defp compile_property(property_line) do
    n = System.unique_integer([:positive])
    name = "AshR2RML.ResourceDslFixesTest.Gen#{n}"

    source = """
    defmodule #{name} do
      use Ash.Resource, domain: nil, data_layer: Ash.DataLayer.Ets, extensions: [AshR2RML.Resource]

      attributes do
        uuid_primary_key :id
        attribute :title, :string, public?: true
        attribute :lang, :string, public?: true
      end

      r2rml do
        table_name("gen_#{n}")
        class("https://schema.org/Thing")

        subject template: "urn:uuid:{id}"

        #{property_line}
      end
    end
    """

    try do
      Code.compile_string(source)
      {:ok, Module.concat([name])}
    rescue
      error -> {:error, Exception.message(error)}
    end
  end

  describe "conflicting term map options are refused" do
    test "positive control: language alone compiles to a language-tagged literal" do
      assert %ObjectMap{language: "en", datatype: nil, term_type: :literal} =
               hd(Info.mapping!(LangOnly).predicate_object_maps).object_map
    end

    test "positive control: datatype alone compiles" do
      assert {:ok, mod} =
               compile_property(
                 ~s|property(:title, "http://purl.org/dc/terms/title", datatype: "http://www.w3.org/2001/XMLSchema#string")|
               )

      assert %ObjectMap{datatype: datatype} = hd(Info.mapping!(mod).predicate_object_maps).object_map
      assert is_binary(datatype) or not is_nil(datatype)
    end

    test "constant + template" do
      assert {:error, message} =
               compile_property(
                 ~s|property(:title, "http://purl.org/dc/terms/title", constant: "a", template: "b/{title}", term_type: :iri)|
               )

      assert message =~ "constant and template"
    end

    test "language + datatype" do
      assert {:error, message} =
               compile_property(
                 ~s|property(:title, "http://purl.org/dc/terms/title", language: "en", datatype: "http://www.w3.org/2001/XMLSchema#string")|
               )

      assert message =~ "language and datatype"
    end

    test "language + language_column" do
      assert {:error, message} =
               compile_property(
                 ~s|property(:title, "http://purl.org/dc/terms/title", language: "en", language_column: :lang)|
               )

      assert message =~ "language and language_column"
    end

    test "datatype with term_type :iri and :blank_node" do
      for tt <- [:iri, :blank_node] do
        assert {:error, message} =
                 compile_property(
                   ~s|property(:title, "http://purl.org/dc/terms/title", datatype: "http://www.w3.org/2001/XMLSchema#string", term_type: :#{tt})|
                 )

        assert message =~ "datatype with term_type #{tt}"
      end
    end
  end

  describe "DSL has_many joins" do
    test "join columns come from the declared attributes, not a guessed kids_id" do
      assert [%ReferenceObjectMap{joins: [join]}] = Info.mapping!(Owner).reference_object_maps
      assert join.child == "id"
      assert join.parent == "owner_id"
    end
  end
end
