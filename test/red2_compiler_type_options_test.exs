# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Red2CompilerTypeOptionsTest do
  use ExUnit.Case, async: false

  @compiler Path.expand("../lib/ash_r2rml/compiler.ex", __DIR__)

  defp compile_type(opts_source) do
    n = System.unique_integer([:positive])

    source = """
    defmodule AshR2RML.Red2Gen.Type#{n} do
      use AshR2RML.Type, #{opts_source}
    end
    """

    try do
      Code.compile_string(source)
      :compiled
    rescue
      error -> {:raised, error}
    end
  end

  describe "compile/2 options" do
    test "any option is refused with a typed refusal (finding FALSE)" do
      assert {:error, %AshR2RML.Refusal{code: :REFUSED_INVALID_OPTION}} =
               AshR2RML.Compiler.compile([], strict: true)
    end

    test "domain detection uses the public Spark.Dsl.is?/2, not spark_is internals" do
      source = File.read!(@compiler)
      refute source =~ "spark_is"
    end
  end

  describe "use AshR2RML.Type option validation" do
    test "unknown option key raises ArgumentError at compile time" do
      assert {:raised, %ArgumentError{}} = compile_type(~s|datatype: "http://www.w3.org/2001/XMLSchema#string"|)
    end

    test "invalid semantic_kind raises ArgumentError at compile time" do
      assert {:raised, %ArgumentError{}} = compile_type("semantic_kind: :bogus")
    end

    test "valid options still compile" do
      assert :compiled = compile_type("semantic_kind: :iri")
    end
  end

  describe "Subject honors AshR2RML.Type lexical callbacks" do
    test "template subject renders and inverts through to_rdf_lexical/from_rdf_lexical" do
      n = System.unique_integer([:positive])

      source = """
      defmodule AshR2RML.Red2Gen.Sku#{n} do
        use Ash.Type
        use AshR2RML.Type, datatype_iri: "http://www.w3.org/2001/XMLSchema#string"

        @impl Ash.Type
        def storage_type(_), do: :string

        @impl Ash.Type
        def cast_input(nil, _), do: {:ok, nil}
        def cast_input({:sku, _} = v, _), do: {:ok, v}
        def cast_input(v, _) when is_binary(v), do: {:ok, {:sku, v}}
        def cast_input(_, _), do: :error

        @impl Ash.Type
        def cast_stored(nil, _), do: {:ok, nil}
        def cast_stored(v, _) when is_binary(v), do: {:ok, {:sku, v}}
        def cast_stored(_, _), do: :error

        @impl Ash.Type
        def dump_to_native(nil, _), do: {:ok, nil}
        def dump_to_native({:sku, v}, _), do: {:ok, v}
        def dump_to_native(_, _), do: :error

        @impl AshR2RML.Type
        def to_rdf_lexical({:sku, v}), do: "SKU-" <> v

        @impl AshR2RML.Type
        def from_rdf_lexical("SKU-" <> v), do: {:ok, {:sku, v}}
        def from_rdf_lexical(_), do: {:error, :bad_sku}
      end

      defmodule AshR2RML.Red2Gen.Item#{n} do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshR2RML.Resource]

        attributes do
          attribute :code, AshR2RML.Red2Gen.Sku#{n},
            primary_key?: true,
            allow_nil?: false,
            public?: true
        end

        r2rml do
          table_name("red2_items_#{n}")
          class("https://schema.org/Thing")
          subject template: "urn:uuid:{code}"
        end
      end
      """

      Code.compile_string(source)
      item = Module.concat(["AshR2RML.Red2Gen.Item#{n}"])

      assert {:ok, "urn:uuid:SKU-ab"} = AshR2RML.Subject.to_iri(item, %{code: "ab"})
      assert {:ok, %{code: {:sku, "ab"}}} = AshR2RML.Subject.from_iri(item, "urn:uuid:SKU-ab")
    end
  end
end
