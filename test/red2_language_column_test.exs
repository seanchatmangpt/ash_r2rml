# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Red2LanguageColumnTest do
  @moduledoc """
  language_column must name a real attribute and must only combine with a
  literal term map; anything else is refused, never silently coerced.
  """
  use ExUnit.Case, async: true

  alias AshR2RML.Mapping.ObjectMap
  alias AshR2RML.Resource.Info

  defp compile_property(property_line) do
    n = System.unique_integer([:positive])
    name = "AshR2RML.Red2LanguageColumnTest.Gen#{n}"

    source = """
    defmodule #{name} do
      use Ash.Resource, domain: nil, data_layer: Ash.DataLayer.Ets, extensions: [AshR2RML.Resource]

      attributes do
        uuid_primary_key :id
        attribute :title, :string, public?: true
        attribute :lang, :string, public?: true
      end

      r2rml do
        table_name("red2_gen_#{n}")
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

  test "positive control: language_column naming a real attribute compiles to a literal" do
    assert {:ok, mod} =
             compile_property(~s|property(:title, "http://purl.org/dc/terms/title", language_column: :lang)|)

    assert %ObjectMap{term_type: :literal, language: "lang"} =
             hd(Info.mapping!(mod).predicate_object_maps).object_map
  end

  test "language_column naming a nonexistent attribute is refused" do
    assert {:error, _message} =
             compile_property(~s|property(:title, "http://purl.org/dc/terms/title", language_column: :no_such_attr)|)
  end

  test "language_column with term_type :iri is refused, not coerced to a literal" do
    assert {:error, _message} =
             compile_property(
               ~s|property(:title, "http://purl.org/dc/terms/title", language_column: :lang, term_type: :iri)|
             )
  end

  test "language_column with term_type :blank_node is refused" do
    assert {:error, _message} =
             compile_property(
               ~s|property(:title, "http://purl.org/dc/terms/title", language_column: :lang, term_type: :blank_node)|
             )
  end
end
