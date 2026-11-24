# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.PersistMappingTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  # Compiles a real resource source file written to tmp_dir; returns the module.
  defp compile_resource!(dir, name, r2rml_body, extra \\ "") do
    mod = "AshR2RML.PersistMappingTest.#{name}"

    source = """
    defmodule #{mod} do
      use Ash.Resource,
        domain: nil,
        validate_domain_inclusion?: false,
        data_layer: Ash.DataLayer.Ets,
        extensions: [AshR2RML]

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
    #{extra}
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
          class_iri "https://example.org/Thing"
          subject_template "https://example.org/thing/{id}"
          table_name "things"
          attribute_mappings [{:name, "https://example.org/name"}, {:display_name, "https://example.org/dn"}]
          typed_attribute_mappings [{:age, "https://example.org/age", "http://www.w3.org/2001/XMLSchema#integer"}]
      """)

    m = mod.__ash_r2rml_mapping__()

    assert m.resource == mod
    assert m.class_iri == "https://example.org/Thing"
    assert m.subject_template == "https://example.org/thing/{id}"
    assert m.logical_table == {:table, "things"}
    assert m.graph_iri == nil

    by_attr = Map.new(m.attributes, &{&1.attribute, &1})
    assert by_attr[:name].column == "name"
    assert by_attr[:name].datatype_iri == nil
    assert by_attr[:display_name].column == "display_name"
    assert by_attr[:age].datatype_iri == "http://www.w3.org/2001/XMLSchema#integer"
    assert by_attr[:age].predicate_iri == "https://example.org/age"
    assert length(m.attributes) == 3
  end

  test "persists sql_query logical table and graph iri", %{tmp_dir: dir} do
    mod =
      compile_resource!(dir, "QueryRes", """
          class_iri "https://example.org/Thing"
          subject_template "https://example.org/thing/{id}"
          sql_query "SELECT id, name FROM things"
          graph_iri "https://example.org/graph"
      """)

    m = mod.__ash_r2rml_mapping__()
    assert m.logical_table == {:sql_query, "SELECT id, name FROM things"}
    assert m.graph_iri == "https://example.org/graph"
    assert m.attributes == []
    assert m.relationships == []
  end

  test "grand example fixture persists a mapping struct", _ctx do
    m = AshR2RML.GrandExample.Organization.__ash_r2rml_mapping__()

    assert m.resource == AshR2RML.GrandExample.Organization
    assert m.logical_table == {:table, "schema_organizations"}
    assert m.class_iri == "https://schema.org/Organization"

    assert Enum.map(m.attributes, & &1.predicate_iri) |> Enum.sort() ==
             ["https://schema.org/name", "https://schema.org/version"]
  end
end
