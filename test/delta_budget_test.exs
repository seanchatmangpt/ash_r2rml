# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.DeltaBudgetTest do
  @moduledoc """
  Asserted budgets for the differential ΔG projection (`AshR2RML.Delta` + the
  `previous_graph:` option of `AshR2RML.OBDA.InMemory.materialize_many/2`).

  Chicago-style: real `Ash.DataLayer.Ets` rows (dedicated private table, so the row
  count per tier is exact -- no cross-test pollution), real `Ash.create!`/`Ash.read!`,
  real `materialize_many/2`, real `AshR2RML.Delta.diff/2` with its real SHA-256
  digest. `:timer.tc` measurements; no Benchee (the bench/ scripts explore, this
  suite asserts).

  Budget law (per the loops-of-loops spec): measure, print, assert. The 20 ms spec
  budget at the 100-row tier is asserted *directly* (both diff+digest and
  materialize+diff combined); every tier additionally asserts a 5x-median outlier
  guard (the generous CI multiplier) so a pathological regression on any tier fails
  even where no absolute budget is pinned. Measured medians are printed on every run
  and recorded in the `AshR2RML.Delta` moduledoc's budget table.
  """

  use ExUnit.Case, async: true

  alias AshR2RML.Delta
  alias AshR2RML.OBDA.InMemory

  defmodule BudgetDomain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.DeltaBudgetTest.BudgetEntity
    end
  end

  # Dedicated resource => dedicated ETS table (`private?: true` scopes it to this
  # test process) => the materialized triple count is a pure function of the rows
  # this test created, which is what makes the tier budgets meaningful.
  defmodule BudgetEntity do
    use Ash.Resource,
      domain: AshR2RML.DeltaBudgetTest.BudgetDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML]

    ets do
      private? true
    end

    r2rml do
      class_iri("https://example.org/ontology/BudgetEntity")
      subject_template("https://example.org/budget/{id}")
      table_name("budget_entities")

      attribute_mappings([
        {:name, "https://schema.org/name"},
        {:version, "https://schema.org/version"}
      ])
    end

    actions do
      defaults [:read, :destroy]

      create :create do
        primary? true
        accept [:name, :version]
      end

      update :update do
        accept [:name, :version]
        primary? true
      end
    end

    attributes do
      uuid_primary_key :id
      attribute :name, :string, allow_nil?: false, public?: true
      attribute :version, :string, allow_nil?: false, public?: true
    end
  end

  @tiers [10, 100, 1000]
  @iterations Delta.default_iterations()
  @spec_budget_ms Delta.spec_budget_ms()
  @outlier_multiplier 5

  @mapping_result AshR2RML.Resource.Info.mapping_result(AshR2RML.DeltaBudgetTest.BudgetEntity)

  setup do
    {:ok, mapping} = @mapping_result
    %{mapping: mapping}
  end

  @rdf_type RDF.iri("http://www.w3.org/1999/02/22-rdf-syntax-ns#type")
  @class_iri RDF.iri("https://example.org/ontology/BudgetEntity")
  @name_iri RDF.iri("https://schema.org/name")
  @version_iri RDF.iri("https://schema.org/version")

  test "diff computes the exact triple-set algebra over real materializations", %{mapping: mapping} do
    seed(3, "v0")
    {:ok, old_graph} = InMemory.materialize(BudgetEntity, mapping, domain: BudgetDomain)

    # Change the world for real: update one row's name, destroy one row, create one row.
    [destroyed, updated, _kept] =
      BudgetEntity |> Ash.read!(domain: BudgetDomain) |> Enum.sort_by(& &1.name)

    updated
    |> Ash.Changeset.for_update(:update, %{name: "row-updated-v1"}, domain: BudgetDomain)
    |> Ash.update!(domain: BudgetDomain)

    destroyed
    |> Ash.Changeset.for_destroy(:destroy, %{}, domain: BudgetDomain)
    |> Ash.destroy!(domain: BudgetDomain)

    created =
      BudgetEntity
      |> Ash.Changeset.for_create(:create, %{name: "row-created", version: "v0"}, domain: BudgetDomain)
      |> Ash.create!(domain: BudgetDomain)

    {:ok, new_graph} = InMemory.materialize(BudgetEntity, mapping, domain: BudgetDomain)
    delta = Delta.diff(old_graph, new_graph)

    subject = fn row -> RDF.iri("https://example.org/budget/#{row.id}") end

    # added: the created row's full triple set + the updated row's new name triple
    assert {subject.(created), @rdf_type, @class_iri} in delta.added
    assert {subject.(created), @name_iri, RDF.literal("row-created")} in delta.added
    assert {subject.(created), @version_iri, RDF.literal("v0")} in delta.added
    assert {subject.(updated), @name_iri, RDF.literal("row-updated-v1")} in delta.added
    assert length(delta.added) == 4

    # removed: the destroyed row's full triple set + the updated row's old name triple
    assert {subject.(destroyed), @rdf_type, @class_iri} in delta.removed
    assert {subject.(destroyed), @name_iri, RDF.literal("row-000001")} in delta.removed
    assert {subject.(destroyed), @version_iri, RDF.literal("v0")} in delta.removed
    assert {subject.(updated), @name_iri, RDF.literal("row-000002")} in delta.removed
    assert length(delta.removed) == 4

    # unchanged: kept row's 3 triples + updated row's type and version = 5
    assert delta.unchanged_count == 5

    assert delta.root_digest == Delta.root_digest(new_graph)
    assert String.starts_with?(delta.root_digest, "sha256:")

    # Deterministic: same inputs, byte-identical delta.
    assert Delta.diff(old_graph, new_graph) == delta
  end

  test "identical graphs produce an empty delta with a stable root digest", %{mapping: mapping} do
    seed(5, "v0")
    {:ok, graph} = InMemory.materialize(BudgetEntity, mapping, domain: BudgetDomain)

    delta = Delta.diff(graph, graph)

    assert delta.added == []
    assert delta.removed == []
    assert delta.unchanged_count == RDF.Graph.triples(graph) |> length()
    assert delta.root_digest == Delta.root_digest(graph)
  end

  test "materialize_many: previous_graph returns {:ok, %{graph, delta}}; absent returns {:ok, graph}", %{
    mapping: mapping
  } do
    seed(4, "v0")
    {:ok, old_graph} = InMemory.materialize(BudgetEntity, mapping, domain: BudgetDomain)

    created =
      BudgetEntity
      |> Ash.Changeset.for_create(:create, %{name: "delta-wired", version: "v1"}, domain: BudgetDomain)
      |> Ash.create!(domain: BudgetDomain)

    assert {:ok, %RDF.Graph{} = plain} =
             InMemory.materialize_many([{BudgetEntity, mapping}], domain: BudgetDomain)

    assert {:ok, %{graph: %RDF.Graph{} = graph, delta: delta}} =
             InMemory.materialize_many([{BudgetEntity, mapping}],
               domain: BudgetDomain,
               previous_graph: old_graph
             )

    # Same world, so the wired path returns exactly the graph the plain path does.
    assert graph == plain

    # added: exactly the created row's 3 triples; nothing removed.
    assert length(delta.added) == 3
    assert {RDF.iri("https://example.org/budget/#{created.id}"), @name_iri, RDF.literal("delta-wired")} in delta.added
    assert delta.removed == []
    assert delta.root_digest == Delta.root_digest(graph)
  end

  test "budget tiers 10/100/1000: measure, print, assert the 20 ms spec budget at 100 rows" do
    results = Enum.map(@tiers, &measure_tier/1)

    IO.puts("""

    --- Delta budget (median of #{@iterations} iterations, real ETS materialize + real diff) ---
    #{format_results(results)}
    """)

    {_n, diff_100, combined_100} = Enum.find(results, fn {n, _d, _c} -> n == 100 end)

    # The spec budgets, asserted directly (this machine):
    assert diff_100 <= @spec_budget_ms,
           "diff+digest at 100 rows took #{diff_100} ms; spec budget is #{@spec_budget_ms} ms"

    assert combined_100 <= @spec_budget_ms,
           "materialize+diff combined at 100 rows took #{combined_100} ms; spec budget is #{@spec_budget_ms} ms"

    # Per-tier outlier guard: the generous CI multiplier (5x) applied to a
    # linear-scaling expectation from the measured 100-row medians. The 10-row tier
    # is floored so a near-zero 100-row median cannot make the bound tighter than
    # the multiplier itself; the 1000-row tier fails here if the digest path went
    # superlinear.
    for {n, diff_ms, combined_ms} <- results do
      scale = max(n / 100, 1.0)

      assert diff_ms <= @outlier_multiplier * max(diff_100 * scale, 0.05),
             "diff+digest at #{n} rows took #{diff_ms} ms; > #{@outlier_multiplier}x the linear expectation from the 100-row median (#{diff_100} ms x #{scale})"

      assert combined_ms <= @outlier_multiplier * max(combined_100 * scale, 0.2),
             "materialize+diff at #{n} rows took #{combined_ms} ms; > #{@outlier_multiplier}x the linear expectation from the 100-row median (#{combined_100} ms x #{scale})"
    end
  end

  # -- measurement ------------------------------------------------------------

  defp measure_tier(n) do
    seed(n, "v0")
    {:ok, old_graph} = InMemory.materialize(BudgetEntity, mapping(), domain: BudgetDomain)

    # Mutate the real world: churn ceil(n/10) rows (update half, destroy the rest),
    # then create the same number back so the row count returns to n.
    churn = max(div(n, 10), 1)
    rows = BudgetEntity |> Ash.read!(domain: BudgetDomain) |> Enum.take(churn)
    {to_update, to_destroy} = Enum.split(rows, churn - div(churn, 2))

    Enum.each(to_update, fn row ->
      row
      |> Ash.Changeset.for_update(:update, %{name: row.name <> "-v1"}, domain: BudgetDomain)
      |> Ash.update!(domain: BudgetDomain)
    end)

    Enum.each(to_destroy, fn row ->
      row |> Ash.Changeset.for_destroy(:destroy, %{}, domain: BudgetDomain) |> Ash.destroy!(domain: BudgetDomain)
    end)

    for i <- 1..churn do
      BudgetEntity
      |> Ash.Changeset.for_create(:create, %{name: "row-churn-#{n}-#{i}", version: "v0"}, domain: BudgetDomain)
      |> Ash.create!(domain: BudgetDomain)
    end

    {:ok, new_graph} = InMemory.materialize(BudgetEntity, mapping(), domain: BudgetDomain)

    # diff+digest: pure function of the two graphs, so iterations reuse them.
    diff_ms = median_for(@iterations, fn -> Delta.diff(old_graph, new_graph) end)

    # combined: a fresh real materialize + the diff, per iteration.
    combined_ms =
      median_for(@iterations, fn ->
        {:ok, fresh_graph} = InMemory.materialize(BudgetEntity, mapping(), domain: BudgetDomain)
        Delta.diff(old_graph, fresh_graph)
      end)

    {n, diff_ms, combined_ms}
  end

  defp median_for(iterations, fun) do
    for _ <- 1..iterations do
      {us, _result} = :timer.tc(fun)
      us / 1000.0
    end
    |> Enum.sort()
    |> Enum.at(div(iterations, 2))
  end

  defp mapping do
    {:ok, mapping} = @mapping_result
    mapping
  end

  defp seed(n, version) do
    for i <- 1..n do
      BudgetEntity
      |> Ash.Changeset.for_create(
        :create,
        %{name: "row-#{String.pad_leading(Integer.to_string(i), 6, "0")}", version: version},
        domain: BudgetDomain
      )
      |> Ash.create!(domain: BudgetDomain)
    end

    :ok
  end

  defp format_results(results) do
    Enum.map_join(results, "\n", fn {n, diff_ms, combined_ms} ->
      :io_lib.format("~5B rows   diff+digest: ~8.3f ms   materialize+diff: ~8.3f ms", [n, diff_ms, combined_ms])
    end)
  end
end
