# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW11TypesLensTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Datatype.Registry

  defmodule Color do
    use Ash.Type.Enum, values: [:red, :green]
  end

  test "explicit datatype override keeps the enum's default storage type" do
    assert {:ok, plain} = Registry.resolve(Color)
    assert {:ok, overridden} = Registry.resolve(Color, "http://schema.org/Text")
    assert overridden.rdf_datatype == "http://schema.org/Text"
    assert overridden.storage_type == plain.storage_type
    assert overridden.storage_type == :text
  end

  test "explicit datatype override keeps the builtin storage type" do
    assert {:ok, dt} = Registry.resolve(Ash.Type.Integer, "http://schema.org/Integer")
    assert dt.storage_type == :bigint
  end
end
