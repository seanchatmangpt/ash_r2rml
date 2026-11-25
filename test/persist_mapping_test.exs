# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.PersistMappingTest do
  @moduledoc """
  The canonical `AshR2RML.Resource` transformer persists a normalized
  `AshR2RML.Mapping.Resource` readable through `AshR2RML.Resource.Info`.
  """
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  # Compiles a real resource source file written to tmp_dir; returns the module.
  defp compile_resource!(dir, name, r2rml_body) do
    mod = "AshR2RML.PersistMappingTest.#{name}"

    source = """
    defmodule #{mod} do
      use Ash.Resource,
        domain: nil,
        validate_domain_inclusion?: false,
        data_layer: Ash.DataLayer.Ets,
        extensions: [AshR2RML.Resource]

      ets do
        private? true
      end

      r2rml do
    #{r2rml_body}
      end

      actions do
        defaults [:read]
      end

      attributes do
        uuid_primary_key :id
        attribute :name, :string, public?: true
        attribute :display_name, :string, public?: true, source: :disp_nm
        attribute :age, :integer, public?: true
      end
    end
    """

    path = Path.join(dir, "#{name}.ex")
    File.write!(path, source)
    Code.compile_file(path)
    Module.concat([mod])
  end

  test "persists table-backed mapping with attribute columns and datatypes", %{tmp_dir: dir} do
    mod =
      compile_resource!(dir, "TableRes", """
          table_name "things"
          class "https://schema.org/Thing"
          subject template: "urn:uuid:{id}"
          property :name, "https://schema.org/name"
          property :display_name, "https://schema.org/alternateName"
          property :age, "https://schema.org/age", datatype: "http://www.w3.org/2001/XMLSchema#integer"
      """)

    assert {:ok, m} = AshR2RML.Resource.Info.mapping_result(mod)

    assert m.ash_resource == mod
    assert m.class_iris == ["https://schema.org/Thing"]
    assert m.subject_map.value == "urn:uuid:{id}"
    assert m.logical_table == %AshR2RML.Mapping.LogicalTable{table_name: "things"}
    assert m.graph_maps == []

    by_attr = Map.new(m.predicate_object_maps, &{&1.attribute, &1})
    assert by_attr[:name].object_map.value == "name"
    assert by_attr[:display_name].object_map.value == "disp_nm"
    assert by_attr[:age].predicate_iri == "https://schema.org/age"
    assert by_attr[:age].object_map.datatype.rdf_datatype == "http://www.w3.org/2001/XMLSchema#integer"
    assert length(m.predicate_object_maps) == 3
  end

  test "persists sql_query logical table and graph iri", %{tmp_dir: dir} do
    mod =
      compile_resource!(dir, "QueryRes", """
          sql_query "SELECT id, name FROM things"
          class "https://schema.org/Thing"
          subject template: "urn:uuid:{id}"
          graph "urn:uuid:00000000-0000-4000-8000-000000000001"
      """)

    assert {:ok, m} = AshR2RML.Resource.Info.mapping_result(mod)
    assert m.logical_table == %AshR2RML.Mapping.LogicalTable{sql_query: "SELECT id, name FROM things"}
    assert [%{value: "urn:uuid:00000000-0000-4000-8000-000000000001"}] = m.graph_maps
    assert m.predicate_object_maps == []
    assert m.reference_object_maps == []
  end

  test "grand example fixture persists a normalized mapping", _ctx do
    assert {:ok, m} = AshR2RML.Resource.Info.mapping_result(AshR2RML.GrandExample.Organization)

    assert m.ash_resource == AshR2RML.GrandExample.Organization
    assert m.logical_table == %AshR2RML.Mapping.LogicalTable{table_name: "schema_organizations"}
    assert m.class_iris == ["https://schema.org/Organization"]

    assert Enum.map(m.predicate_object_maps, & &1.predicate_iri) |> Enum.sort() ==
             ["https://schema.org/name", "https://schema.org/version"]
  end
end
