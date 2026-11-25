# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.VerifyMappingTest do
  @moduledoc """
  Real resource source files compiled against the one canonical DSL
  (`AshR2RML.Resource`): every refusal surfaces from the transformer or from the
  `Mapping.normalize/1` + `Mapping.validate/1` verifier path.
  """
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  @valid """
      table_name "things"
      class "https://schema.org/Thing"
      subject template: "urn:uuid:{id}"
  """

  # Writes a real resource source file and compiles it. Returns {:ok, module}
  # or {:error, message} when the transformer or the Spark verifier refuses.
  defp compile(dir, name, r2rml_body) do
    mod = "AshR2RML.VerifyMappingTest.#{name}"

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

    assert {:ok, mapping} = AshR2RML.Resource.Info.mapping_result(mod)
    assert mapping.logical_table == %AshR2RML.Mapping.LogicalTable{table_name: "things"}
    assert AshR2RML.Mapping.validate(mapping) == :ok
  end

  test "refuses a missing subject map", %{tmp_dir: dir} do
    assert {:error, msg} =
             compile(dir, "NoSubject", """
                 table_name "things"
                 class "https://schema.org/Thing"
             """)

    assert msg =~ "subject mapping is required"
  end

  test "refuses when both table_name and sql_query are set", %{tmp_dir: dir} do
    assert {:error, msg} = compile(dir, "BothTables", @valid <> "    sql_query \"SELECT 1\"\n")
    assert msg =~ "exactly one of table_name or sql_query"
  end

  test "refuses relative class IRI", %{tmp_dir: dir} do
    assert {:error, msg} =
             compile(dir, "RelClass", """
                 table_name "things"
                 class "relative/Thing"
                 subject template: "urn:uuid:{id}"
             """)

    assert msg =~ "REFUSED_INVALID_CLASS_IRI"
  end

  test "refuses relative graph IRI", %{tmp_dir: dir} do
    assert {:error, msg} = compile(dir, "RelGraph", @valid <> "    graph \"rel/graph\"\n")
    assert msg =~ "REFUSED_INVALID_GRAPH_MAP"
  end

  test "refuses relative predicate IRI", %{tmp_dir: dir} do
    assert {:error, msg} = compile(dir, "RelPred", @valid <> "    property :name, \"name\"\n")
    assert msg =~ "predicate IRI must be absolute"
  end

  test "refuses unknown attribute", %{tmp_dir: dir} do
    assert {:error, msg} =
             compile(dir, "UnknownAttr", @valid <> "    property :ghost, \"https://schema.org/name\"\n")

    assert msg =~ "unknown Ash attribute"
  end

  test "refuses unknown relationship", %{tmp_dir: dir} do
    assert {:error, msg} =
             compile(dir, "UnknownRel", @valid <> "    reference :ghost, \"https://schema.org/knows\"\n")

    assert msg =~ "Ash relationship does not exist"
  end

  test "refuses duplicate attribute mapping", %{tmp_dir: dir} do
    assert {:error, msg} =
             compile(
               dir,
               "DupAttr",
               @valid <>
                 "    property :name, \"https://schema.org/name\"\n    property :name, \"https://schema.org/name\"\n"
             )

    assert msg =~ ~r/duplicate/i
  end

  test "refuses a subject template that omits the primary key placeholder", %{tmp_dir: dir} do
    assert {:error, msg} =
             compile(dir, "NoPk", """
                 table_name "things"
                 class "https://schema.org/Thing"
                 subject template: "urn:uuid:{name}"
             """)

    assert msg =~ "REFUSED_NON_UNIQUE_SEMANTIC_IDENTITY"
  end
end
