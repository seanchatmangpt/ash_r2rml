# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.VerifyMappingTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  @valid """
      class_iri "https://example.org/Thing"
      subject_template "https://example.org/thing/{id}"
      table_name "things"
  """

  # Writes a real resource source file and compiles it. Returns {:ok, module}
  # or {:error, exception message} when the Spark verifier refuses.
  defp compile(dir, name, r2rml_body) do
    mod = "AshR2RML.VerifyMappingTest.#{name}"

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
      end
    end
    """

    path = Path.join(dir, "#{name}.ex")
    File.write!(path, source)

    # Spark verifier failures surface as DslError warnings on stderr during compilation.
    {result, stderr} =
      ExUnit.CaptureIO.with_io(:stderr, fn ->
        try do
          Code.compile_file(path)
          :compiled
        rescue
          e -> {:raised, Exception.message(e)}
        end
      end)

    cond do
      match?({:raised, _}, result) -> {:error, elem(result, 1)}
      String.contains?(stderr, "Spark.Error.DslError") -> {:error, stderr}
      true -> {:ok, Module.concat([mod])}
    end
  end

  test "accepts a valid mapping", %{tmp_dir: dir} do
    assert {:ok, mod} = compile(dir, "Valid", @valid)
    assert mod.__ash_r2rml_mapping__().logical_table == {:table, "things"}
  end

  test "refuses when neither table_name nor sql_query is set", %{tmp_dir: dir} do
    assert {:error, msg} =
             compile(dir, "NoTable", """
                 class_iri "https://example.org/Thing"
                 subject_template "https://example.org/thing/{id}"
             """)

    assert msg =~ "exactly one of table_name or sql_query"
  end

  test "refuses when both table_name and sql_query are set", %{tmp_dir: dir} do
    assert {:error, msg} = compile(dir, "BothTables", @valid <> "    sql_query \"SELECT 1\"\n")
    assert msg =~ "exactly one of table_name or sql_query"
  end

  test "refuses relative class_iri", %{tmp_dir: dir} do
    assert {:error, msg} =
             compile(dir, "RelClass", """
                 class_iri "relative/Thing"
                 subject_template "https://example.org/thing/{id}"
                 table_name "things"
             """)

    assert msg =~ "class_iri must be an absolute IRI"
  end

  test "refuses relative graph_iri", %{tmp_dir: dir} do
    assert {:error, msg} = compile(dir, "RelGraph", @valid <> "    graph_iri \"rel/graph\"\n")
    assert msg =~ "graph_iri must be an absolute IRI"
  end

  test "refuses relative predicate IRI", %{tmp_dir: dir} do
    assert {:error, msg} =
             compile(dir, "RelPred", @valid <> "    attribute_mappings [{:name, \"name\"}]\n")

    assert msg =~ "absolute IRI"
  end

  test "refuses unknown attribute", %{tmp_dir: dir} do
    assert {:error, msg} =
             compile(
               dir,
               "UnknownAttr",
               @valid <> "    attribute_mappings [{:ghost, \"https://example.org/g\"}]\n"
             )

    assert msg =~ "unknown attributes"
    assert msg =~ ":ghost"
  end

  test "refuses unknown relationship", %{tmp_dir: dir} do
    assert {:error, msg} =
             compile(
               dir,
               "UnknownRel",
               @valid <> "    relationship_mappings [{:ghost, \"https://example.org/g\"}]\n"
             )

    assert msg =~ "relationship mappings must reference relationships"
  end

  test "refuses duplicate attribute mapping", %{tmp_dir: dir} do
    assert {:error, msg} =
             compile(
               dir,
               "DupAttr",
               @valid <>
                 "    attribute_mappings [{:name, \"https://example.org/a\"}, {:name, \"https://example.org/b\"}]\n"
             )

    assert msg =~ "attributes may be mapped only once"
  end

  test "refuses subject_template missing the primary key placeholder", %{tmp_dir: dir} do
    assert {:error, msg} =
             compile(dir, "NoPk", """
                 class_iri "https://example.org/Thing"
                 subject_template "https://example.org/thing/{name}"
                 table_name "things"
             """)

    assert msg =~ "primary-key"
  end
end
