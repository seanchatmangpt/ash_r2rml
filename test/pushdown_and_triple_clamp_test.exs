# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.PushdownAndTripleClampTest do
  @moduledoc """
  `stats.rows_read` is the observable for pushdown: point lookups read one row, filters, sort and
  limit narrow the read, and a wide resource (30 predicates x 5000 rows) under `max_triples`
  25_000 is refused with `REFUSED_TRIPLE_LIMIT_EXCEEDED` before the rows are all read.
  Real `Ash.DataLayer.Ets`; no sleeps, the refusal latency is bounded by a monotonic deadline.
  """
  use ExUnit.Case, async: false

  alias AshR2RML.Mapping.{LogicalTable, ObjectMap, PredicateObjectMap, Resource, SubjectMap}
  alias AshR2RML.OBDA.InMemory

  @ex "urn:uuid:"
  @s "https://schema.org/"
  @narrow_rows 200
  @wide_rows 5000
  @wide_predicates 30
  @wide_max_triples 25_000
  @deadline_ms 30_000

  alias AshR2RML.PushdownAndTripleClampTest.WideDom

  defmodule Dom do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.PushdownAndTripleClampTest.Narrow
    end
  end

  defmodule Narrow do
    use Ash.Resource, domain: AshR2RML.PushdownAndTripleClampTest.Dom, data_layer: Ash.DataLayer.Ets

    ets do
      private? false
    end

    actions do
      defaults [:read]

      create :create do
        primary? true
        accept [:code, :name, :rank]
      end
    end

    attributes do
      attribute :code, :string, primary_key?: true, allow_nil?: false, public?: true
      attribute :name, :string, public?: true
      attribute :rank, :string, public?: true
    end
  end

  defp pad(i, width), do: i |> Integer.to_string() |> String.pad_leading(width, "0")

  # Wide resource built at runtime: 30 string attributes a00..a29, key `id`.
  defp wide_attr_names, do: for(i <- 0..(@wide_predicates - 1), do: String.to_atom("a" <> pad(i, 2)))

  defp define_wide! do
    names = wide_attr_names()

    attrs =
      for name <- names do
        quote do: attribute(unquote(name), :string, public?: true)
      end

    body =
      quote do
        use Ash.Resource,
          domain: AshR2RML.PushdownAndTripleClampTest.WideDom,
          data_layer: Ash.DataLayer.Ets

        ets do
          private? false
        end

        actions do
          defaults [:read]

          create :create do
            primary? true
            accept [:id | unquote(names)]
          end
        end

        attributes do
          attribute :id, :string, primary_key?: true, allow_nil?: false, public?: true
          unquote_splicing(attrs)
        end
      end

    mod = AshR2RML.PushdownAndTripleClampTest.Wide
    {:module, ^mod, _, _} = Module.create(mod, body, Macro.Env.location(__ENV__))

    dom_body =
      quote do
        use Ash.Domain, validate_config_inclusion?: false

        resources do
          resource unquote(mod)
        end
      end

    {:module, _, _, _} = Module.create(WideDom, dom_body, Macro.Env.location(__ENV__))
    mod
  end

  setup_all do
    Ash.DataLayer.Ets.stop(Narrow)

    for i <- 0..(@narrow_rows - 1) do
      Ash.create!(Narrow, %{code: "c" <> pad(i, 3), name: "n" <> pad(i, 3), rank: "r" <> pad(i, 3)}, domain: Dom)
    end

    wide = define_wide!()
    Ash.DataLayer.Ets.stop(wide)

    # Created in this (setup_all) process so it owns the public ETS table for the module's run.
    for i <- 0..(@wide_rows - 1) do
      input = Map.new(wide_attr_names(), &{&1, "v#{i}"}) |> Map.put(:id, "w" <> pad(i, 4))
      Ash.create!(wide, input, domain: WideDom, authorize?: false)
    end

    %{wide: wide}
  end

  defp pom(attribute, predicate) do
    %PredicateObjectMap{
      attribute: attribute,
      predicate_iri: @s <> predicate,
      object_map: %ObjectMap{strategy: :column, value: Atom.to_string(attribute)}
    }
  end

  defp narrow_mapping do
    %Resource{
      ash_resource: Narrow,
      logical_table: %LogicalTable{table_name: "narrow"},
      subject_map: %SubjectMap{strategy: :template, value: @ex <> "narrow-{code}"},
      class_iris: [@s <> "Thing"],
      identities: [[:code]],
      predicate_object_maps: [pom(:name, "name"), pom(:rank, "rank")]
    }
  end

  defp wide_mapping(wide) do
    %Resource{
      ash_resource: wide,
      logical_table: %LogicalTable{table_name: "wide"},
      subject_map: %SubjectMap{strategy: :template, value: @ex <> "wide-{id}"},
      class_iris: [@s <> "Thing"],
      identities: [[:id]],
      predicate_object_maps: Enum.map(wide_attr_names(), &pom(&1, Atom.to_string(&1)))
    }
  end

  defp narrow_query(sparql, extra \\ []) do
    opts = [domain: Dom, authorize?: false, allow_unauthorized: true, timeout_ms: @deadline_ms]
    AshR2RML.OBDA.query([{Narrow, narrow_mapping()}], sparql, opts ++ extra)
  end

  defp val(%RDF.Literal{} = literal), do: RDF.Literal.value(literal)
  defp val(%{value: value}), do: value
  defp val(value), do: value

  describe "point lookup" do
    test "a constant subject IRI reads exactly one row" do
      target = @ex <> "narrow-c" <> pad(123, 3)
      sparql = "SELECT ?name WHERE { <#{target}> <#{@s}name> ?name }"

      assert {:ok, result} = narrow_query(sparql, subject_iri: target)
      assert Enum.map(result.bindings, &val(&1["name"])) == ["n123"]
      assert result.stats.rows_read == 1
    end
  end

  describe "filter, sort and limit push down" do
    test "range FILTER + ORDER BY + LIMIT reads limit + 1 rows, not the table" do
      sparql = """
      SELECT ?name ?rank WHERE { ?e <#{@s}name> ?name ; <#{@s}rank> ?rank .
        FILTER(?rank >= "r050") } ORDER BY ?rank LIMIT 5
      """

      assert {:ok, result} = narrow_query(sparql)

      expected = for i <- 50..54, do: "r" <> pad(i, 3)
      assert Enum.map(result.bindings, &val(&1["rank"])) == expected
      assert result.stats.rows_read < @narrow_rows
      assert result.stats.rows_read == 6
    end

    test "a selective FILTER with ORDER BY reads only the matching rows" do
      sparql = """
      SELECT ?rank WHERE { ?e <#{@s}name> ?name ; <#{@s}rank> ?rank .
        FILTER(?rank >= "r190") } ORDER BY ?rank
      """

      assert {:ok, result} = narrow_query(sparql)
      assert length(result.bindings) == 10
      assert result.stats.rows_read == 10
    end

    test "OFFSET + LIMIT over ORDER BY reads offset + limit + 1 rows" do
      sparql = "SELECT ?name WHERE { ?e <#{@s}name> ?name ; <#{@s}rank> ?r } ORDER BY ?name LIMIT 3 OFFSET 4"

      assert {:ok, result} = narrow_query(sparql)
      assert Enum.map(result.bindings, &val(&1["name"])) == ["n004", "n005", "n006"]
      assert result.stats.rows_read == 8
    end

    test "pushdown: false reads every row and returns the same bindings" do
      sparql = "SELECT ?name WHERE { ?e <#{@s}name> ?name ; <#{@s}rank> ?r } ORDER BY ?name LIMIT 3 OFFSET 4"

      assert {:ok, pushed} = narrow_query(sparql)
      assert {:ok, full} = narrow_query(sparql, pushdown: false)

      assert pushed.bindings == full.bindings
      assert full.stats.rows_read == @narrow_rows
    end
  end

  describe "triple clamp on a 30-predicate x 5000-row resource" do
    test "max_triples 25_000 refuses via OBDA.query within the deadline", %{wide: wide} do
      sparql = "SELECT ?v WHERE { ?s <#{@s}a00> ?v }"
      opts = [domain: WideDom, authorize?: false, allow_unauthorized: true] ++ [timeout_ms: @deadline_ms]
      started = System.monotonic_time(:millisecond)

      assert {:error, %{code: :REFUSED_TRIPLE_LIMIT_EXCEEDED}} =
               AshR2RML.OBDA.query(
                 [{wide, wide_mapping(wide)}],
                 sparql,
                 [max_triples: @wide_max_triples] ++ opts
               )

      assert System.monotonic_time(:millisecond) - started < @deadline_ms
    end

    test "the refusal halts accumulation: rows_read stays below the table size", %{wide: wide} do
      sparql = "SELECT ?v WHERE { ?s <#{@s}a00> ?v }"
      started = System.monotonic_time(:millisecond)

      {outcome, stats} =
        InMemory.query_with_stats([{wide, wide_mapping(wide)}], sparql,
          domain: WideDom,
          authorize?: false,
          allow_unauthorized: true,
          max_triples: @wide_max_triples
        )

      assert {:error, %{code: :REFUSED_TRIPLE_LIMIT_EXCEEDED}} = outcome
      assert System.monotonic_time(:millisecond) - started < @deadline_ms
      assert stats.rows_read < @wide_rows
      # 31 triples per row (class + 30 predicates): never more rows than the budget admits.
      assert stats.rows_read <= div(@wide_max_triples, @wide_predicates + 1) + 1
    end
  end
end
