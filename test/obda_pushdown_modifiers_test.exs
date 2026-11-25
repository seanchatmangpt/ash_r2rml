# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.ObdaPushdownModifiersTest do
  @moduledoc """
  SPARQL solution modifiers and root-resource pushdown, executed through `AshR2RML.OBDA.query/3`
  against real `Ash.DataLayer.Ets` rows (30 employees, 5 teams).

  Expected rows come from an independent `Enum` oracle over the seed data, never from the code
  under test. The `rows_read` assertions in the "narrowed read" group additionally require the
  receiving side of the `:query_pushdown` read option in `AshR2RML.OBDA.InMemory`.
  """

  use ExUnit.Case, async: false

  doctest AshR2RML.QueryBuilder.Modifiers

  alias AshR2RML.Mapping.{
    Datatype,
    JoinCondition,
    LogicalTable,
    ObjectMap,
    PredicateObjectMap,
    ReferenceObjectMap,
    Resource,
    SubjectMap
  }

  alias AshR2RML.QueryBuilder
  alias AshR2RML.QueryBuilder.Modifiers

  @ex "urn:uuid:"
  @s "https://schema.org/"
  @xsd_string "http://www.w3.org/2001/XMLSchema#string"
  @total_subjects 35

  defmodule Dom do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.ObdaPushdownModifiersTest.Team
      resource AshR2RML.ObdaPushdownModifiersTest.Emp
    end
  end

  defmodule Team do
    use Ash.Resource, domain: AshR2RML.ObdaPushdownModifiersTest.Dom, data_layer: Ash.DataLayer.Ets

    actions do
      defaults [:read]

      create :create do
        primary? true
        accept [:tcode, :title]
      end
    end

    attributes do
      attribute :tcode, :string, primary_key?: true, allow_nil?: false, public?: true
      attribute :title, :string, public?: true
    end
  end

  defmodule Emp do
    use Ash.Resource, domain: AshR2RML.ObdaPushdownModifiersTest.Dom, data_layer: Ash.DataLayer.Ets

    actions do
      defaults [:read]

      create :create do
        primary? true
        accept [:code, :name, :rank, :team_code]
      end
    end

    attributes do
      attribute :code, :string, primary_key?: true, allow_nil?: false, public?: true
      attribute :name, :string, public?: true
      attribute :rank, :string, public?: true
      attribute :team_code, :string, public?: true
    end
  end

  # -- seed + oracle ---------------------------------------------------------------------

  defp pad(i), do: i |> Integer.to_string() |> String.pad_leading(2, "0")

  # i in 27..29 reference a team that does not exist, i == 26 has no team, ranks tie in threes.
  defp emp_rows do
    for i <- 0..29 do
      team =
        cond do
          i >= 27 -> "tx"
          i == 26 -> nil
          true -> "t#{rem(i, 5)}"
        end

      %{code: "e" <> pad(i), name: "n" <> pad(rem(i * 7, 30)), rank: "r" <> pad(div(i, 3)), team_code: team}
    end
  end

  defp team_rows, do: for(k <- 0..4, do: %{tcode: "t#{k}", title: "Team #{k}"})

  defp joined_rows do
    for e <- emp_rows(), t <- team_rows(), e.team_code == t.tcode, do: %{name: e.name, rank: e.rank, title: t.title}
  end

  defp by_rank_desc_name(rows) do
    Enum.sort(rows, fn a, b -> {b.rank, a.name} <= {a.rank, b.name} end)
  end

  setup_all do
    for row <- team_rows(), do: Ash.create!(Team, row, domain: Dom)
    for row <- emp_rows(), do: Ash.create!(Emp, row, domain: Dom)
    :ok
  end

  # -- mappings --------------------------------------------------------------------------

  @string_dt %Datatype{ash_type: :string, rdf_datatype: @xsd_string}

  defp pom(attribute, predicate, datatype) do
    %PredicateObjectMap{
      attribute: attribute,
      predicate_iri: @s <> predicate,
      object_map: %ObjectMap{strategy: :column, value: Atom.to_string(attribute), datatype: datatype}
    }
  end

  defp team_mapping do
    %Resource{
      ash_resource: Team,
      logical_table: %LogicalTable{table_name: "team"},
      subject_map: %SubjectMap{strategy: :template, value: @ex <> "team-{tcode}"},
      class_iris: [@s <> "Organization"],
      identities: [[:tcode]],
      predicate_object_maps: [pom(:title, "title", @string_dt)]
    }
  end

  defp emp_mapping do
    %Resource{
      ash_resource: Emp,
      logical_table: %LogicalTable{table_name: "emp"},
      subject_map: %SubjectMap{strategy: :template, value: @ex <> "emp-{code}"},
      class_iris: [@s <> "Person"],
      identities: [[:code]],
      predicate_object_maps: [pom(:name, "name", @string_dt), pom(:rank, "rank", @string_dt)],
      reference_object_maps: [
        %ReferenceObjectMap{
          relationship: :team,
          predicate_iri: @s <> "team",
          parent_resource: Team,
          joins: [%JoinCondition{child: "team_code", parent: "tcode"}]
        }
      ]
    }
  end

  defp specs, do: [{Team, team_mapping()}, {Emp, emp_mapping()}]

  defp run(sparql, extra \\ []) do
    AshR2RML.OBDA.query(specs(), sparql, [domain: Dom, authorize?: false, allow_unauthorized: true] ++ extra)
  end

  defp val(%RDF.Literal{} = literal), do: RDF.Literal.value(literal)
  defp val(%{value: value}), do: value
  defp val(value), do: value

  defp triples(extra_filter, tail) do
    """
    SELECT ?name ?rank ?title WHERE {
      ?e <#{@s}name> ?name ; <#{@s}rank> ?rank ; <#{@s}team> ?t .
      ?t <#{@s}title> ?title .
      #{extra_filter}
    } #{tail}
    """
  end

  defp projected(result),
    do: Enum.map(result.bindings, &%{name: val(&1["name"]), rank: val(&1["rank"]), title: val(&1["title"])})

  # -- Modifiers (pure) ------------------------------------------------------------------

  describe "Modifiers" do
    test "sort is stable, unbound sorts first, mixed directions apply per key" do
      rows = [
        %{"a" => 2, "b" => "x"},
        %{"a" => 1, "b" => "y"},
        %{"b" => "z"},
        %{"a" => 2, "b" => "a"}
      ]

      parsed = {:ok, %{order: [{"a", :desc}, {"b", :asc}], limit: nil, offset: 0}}

      assert Modifiers.run(rows, parsed) == [
               %{"a" => 2, "b" => "a"},
               %{"a" => 2, "b" => "x"},
               %{"a" => 1, "b" => "y"},
               %{"b" => "z"}
             ]
    end

    test "an ORDER BY variable absent from every row leaves the rows untouched" do
      rows = [%{"a" => 2}, %{"a" => 1}]
      assert Modifiers.run(rows, {:ok, %{order: [{"gone", :asc}], limit: nil, offset: 0}}) == rows
    end

    test "offset past the end and LIMIT 0 yield no rows" do
      rows = [%{"a" => 1}, %{"a" => 2}]
      assert Modifiers.run(rows, {:ok, %{order: [], limit: nil, offset: 5}}) == []
      assert Modifiers.run(rows, {:ok, %{order: [], limit: 0, offset: 0}}) == []
    end

    test "braces and LIMIT text inside string literals do not move the tail split" do
      sparql = ~s|SELECT ?x WHERE { ?s ?p "} LIMIT 9" } LIMIT 2|
      assert Modifiers.parse(sparql) == {:ok, %{order: [], limit: 2, offset: 0}}
    end
  end

  # -- lowering (pure) -------------------------------------------------------------------

  describe "lowering" do
    test "a star + reference join + range FILTER + ORDER BY + LIMIT lowers to a root pushdown" do
      sparql = triples(~s|FILTER(?rank >= "r02" && ?rank <= "r07")|, "ORDER BY DESC(?rank) ?name LIMIT 4")

      assert {:ok, pd} = QueryBuilder.lower(sparql, specs())
      assert pd.resource == Emp
      assert {pd.keep, pd.fetch} == {4, 5}
      assert pd.plan.sort == [rank: :desc, name: :asc]
      assert pd.plan.limit == 5
      assert {:and, conditions} = pd.plan.filter
      assert {:gte, :rank, "r02"} in conditions
      assert {:lte, :rank, "r07"} in conditions
      assert {:not_nil, :name, nil} in conditions
      assert :team_code in pd.plan.needed_attributes
    end

    test "every unsure shape falls back" do
      p = @s

      fallbacks = [
        "SELECT ?name WHERE { ?e <#{p}name> ?name OPTIONAL { ?e <#{p}rank> ?rank } } ORDER BY ?name LIMIT 2",
        "SELECT ?name WHERE { { ?e <#{p}name> ?name } UNION { ?e <#{p}rank> ?name } } ORDER BY ?name LIMIT 2",
        "SELECT (COUNT(?name) AS ?c) WHERE { ?e <#{p}name> ?name ; <#{p}rank> ?r } ",
        ~s|SELECT ?name WHERE { ?e <#{p}name> ?name ; <#{p}rank> "r01" } ORDER BY ?name LIMIT 2|,
        "SELECT DISTINCT ?name WHERE { ?e <#{p}name> ?name ; <#{p}rank> ?r } ORDER BY ?name LIMIT 2",
        "SELECT ?name WHERE { ?e <#{p}name> ?name ; <#{p}rank> ?r } LIMIT 2",
        "SELECT ?name WHERE { ?e ?pred ?name } ORDER BY ?name LIMIT 2",
        "SELECT ?name WHERE { ?e <#{p}name> ?name ; <#{p}title> ?r } ORDER BY ?name LIMIT 2",
        ~s|SELECT ?name WHERE { ?e <#{p}name> ?name ; <#{p}team> ?t . ?t <#{p}title> ?title FILTER(?title = "Team 1") }|
      ]

      for sparql <- fallbacks, do: assert(QueryBuilder.lower(sparql, specs()) == :fallback, sparql)
    end

    test "a root resource that is a join parent of any spec is never narrowed" do
      back_reference = %ReferenceObjectMap{
        relationship: :boss,
        predicate_iri: @s <> "boss",
        parent_resource: Emp,
        joins: [%JoinCondition{child: "tcode", parent: "code"}]
      }

      team = %{team_mapping() | reference_object_maps: [back_reference]}
      sparql = "SELECT ?name WHERE { ?e <#{@s}name> ?name ; <#{@s}rank> ?r } ORDER BY ?name LIMIT 2"

      assert {:ok, _} = QueryBuilder.lower(sparql, specs())
      assert QueryBuilder.lower(sparql, [{Team, team}, {Emp, emp_mapping()}]) == :fallback
    end

    test "pushdown_query reads exactly the filtered, sorted, bounded root rows" do
      sparql = "SELECT ?name WHERE { ?e <#{@s}name> ?name ; <#{@s}rank> ?r } ORDER BY ?name LIMIT 3 OFFSET 2"
      assert {:ok, pd} = QueryBuilder.lower(sparql, specs())

      query = QueryBuilder.pushdown_query(pd.resource, pd.mapping, pd.plan, domain: Dom, authorize?: false)
      assert %Ash.Query{} = query

      names = query |> Ash.read!(domain: Dom, authorize?: false) |> Enum.map(& &1.name)
      assert names == emp_rows() |> Enum.map(& &1.name) |> Enum.sort() |> Enum.take(6)
    end
  end

  # -- verification (pure graph, hand-built) ---------------------------------------------

  defp graph(names, literal \\ &RDF.literal/1) do
    names
    |> Enum.with_index()
    |> Enum.reduce(RDF.Graph.new(), fn {name, i}, acc ->
      RDF.Graph.add(acc, {RDF.iri(@ex <> "emp-e#{pad(i)}"), RDF.iri(@s <> "name"), literal.(name)})
    end)
  end

  describe "verify" do
    setup do
      sparql = "SELECT ?name WHERE { ?e <#{@s}name> ?name ; <#{@s}rank> ?r } ORDER BY ?name LIMIT 3 OFFSET 2"
      {:ok, pd} = QueryBuilder.lower(sparql, specs())
      %{pd: pd}
    end

    test "an exhaustive read is accepted", %{pd: pd} do
      assert QueryBuilder.verify(pd, graph(["n00", "n01", "n02"]), 0) == :ok
    end

    test "a truncated read needs keep solutions", %{pd: pd} do
      six = graph(["n00", "n01", "n02", "n03", "n04", "n05"])
      assert QueryBuilder.verify(pd, six, 5) == :ok
      assert QueryBuilder.verify(pd, six, 4) == :fallback
    end

    test "a tie between the last kept row and the sentinel forces a full re-read", %{pd: pd} do
      tied = graph(["n00", "n01", "n02", "n03", "n04", "n04"])
      assert QueryBuilder.verify(pd, tied, 6) == :fallback
    end

    test "key literals that are not typed as the mapping declares force a full re-read", %{pd: pd} do
      untyped = graph([0, 1, 2, 3, 4, 5], &RDF.literal/1)
      assert QueryBuilder.verify(pd, untyped, 6) == :fallback
    end
  end

  # -- end to end through OBDA.query -----------------------------------------------------

  describe "results through OBDA.query" do
    test "range FILTER + join + ORDER BY + LIMIT returns the oracle rows" do
      sparql = triples(~s|FILTER(?rank >= "r02" && ?rank <= "r07")|, "ORDER BY DESC(?rank) ?name LIMIT 4")
      assert {:ok, result} = run(sparql)

      expected =
        joined_rows()
        |> Enum.filter(&(&1.rank >= "r02" and &1.rank <= "r07"))
        |> by_rank_desc_name()
        |> Enum.take(4)

      assert length(expected) == 4
      assert projected(result) == expected
    end

    test "join starvation (top-ranked rows have no team) still returns the oracle rows" do
      sparql = triples(~s|FILTER(?rank >= "r02")|, "ORDER BY DESC(?rank) ?name LIMIT 4")
      assert {:ok, result} = run(sparql)

      expected = joined_rows() |> Enum.filter(&(&1.rank >= "r02")) |> by_rank_desc_name() |> Enum.take(4)

      assert projected(result) == expected
      assert Enum.map(projected(result), & &1.rank) == ["r08", "r08", "r07", "r07"]
    end

    test "a tie at the LIMIT boundary returns the oracle rank multiset" do
      sparql = "SELECT ?rank WHERE { ?e <#{@s}rank> ?rank ; <#{@s}name> ?name } ORDER BY DESC(?rank) LIMIT 4"
      assert {:ok, result} = run(sparql)

      expected = emp_rows() |> Enum.map(& &1.rank) |> Enum.sort(:desc) |> Enum.take(4)
      assert Enum.map(result.bindings, &val(&1["rank"])) == expected
      assert expected == ["r09", "r09", "r09", "r08"]
    end

    test "OFFSET + LIMIT over ORDER BY returns the oracle window" do
      sparql = "SELECT ?name WHERE { ?e <#{@s}name> ?name ; <#{@s}rank> ?rank } ORDER BY ?name LIMIT 3 OFFSET 2"
      assert {:ok, result} = run(sparql)

      expected = emp_rows() |> Enum.map(& &1.name) |> Enum.sort() |> Enum.slice(2, 3)
      assert Enum.map(result.bindings, &val(&1["name"])) == expected
    end

    test "LIMIT without ORDER BY takes the first rows of the canonical order and reads everything" do
      assert {:ok, result} = run("SELECT ?name WHERE { ?e <#{@s}name> ?name } LIMIT 5")

      expected = emp_rows() |> Enum.map(& &1.name) |> Enum.sort() |> Enum.take(5)
      assert Enum.map(result.bindings, &val(&1["name"])) == expected
      assert result.stats.rows_read == @total_subjects
    end

    test "OPTIONAL falls back to the full read and keeps every employee" do
      sparql = """
      SELECT ?name ?title WHERE {
        ?e <#{@s}name> ?name .
        OPTIONAL { ?e <#{@s}team> ?t . ?t <#{@s}title> ?title }
      }
      """

      assert {:ok, result} = run(sparql)
      assert length(result.bindings) == 30
      assert result.stats.rows_read == @total_subjects
    end

    test "pushdown: false yields the same rows as the default path" do
      sparql = triples(~s|FILTER(?rank >= "r02" && ?rank <= "r07")|, "ORDER BY DESC(?rank) ?name LIMIT 4")
      assert {:ok, pushed} = run(sparql)
      assert {:ok, full} = run(sparql, pushdown: false)

      assert projected(pushed) == projected(full)
      assert full.stats.rows_read == @total_subjects
    end
  end

  # -- narrowed read (needs the :query_pushdown receiver in OBDA.InMemory) ---------------

  describe "narrowed read" do
    test "range FILTER + join + ORDER BY + LIMIT reads a fraction of the rows" do
      sparql = triples(~s|FILTER(?rank >= "r02" && ?rank <= "r07")|, "ORDER BY DESC(?rank) ?name LIMIT 4")
      assert {:ok, result} = run(sparql)

      # 5 root rows (limit + sentinel) + 5 teams
      assert result.stats.rows_read < @total_subjects
      assert result.stats.rows_read == 10
    end

    test "OFFSET + LIMIT reads offset + limit + 1 root rows" do
      sparql = "SELECT ?name WHERE { ?e <#{@s}name> ?name ; <#{@s}rank> ?rank } ORDER BY ?name LIMIT 3 OFFSET 2"
      assert {:ok, result} = run(sparql)

      # 6 root rows + 5 teams
      assert result.stats.rows_read == 11
    end
  end
end
