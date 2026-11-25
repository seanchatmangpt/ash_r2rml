# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.NamedGraphsFourViewsTest do
  @moduledoc """
  One ETS-backed Ash resource projected into four named graph views through a column-valued
  `rr:graphMap` (`:public`, `:donor_cpa`, `:elder_governance`, `:private_syndicate`).

  Visibility is enforced by a real `Ash.Policy.Authorizer` read filter keyed on the actor's
  `:views`, plus attribute multitenancy. Everything is asserted through the public
  `AshR2RML.OBDA.query/3` envelope, including `GRAPH ?g` / `GRAPH <iri>` queries. Written
  against the intended contract: `OBDA.InMemory` places each row's triples in the graph named
  by the mapped column, and `GRAPH` patterns select among them.
  """

  use ExUnit.Case, async: false

  alias AshR2RML.Mapping.{
    Datatype,
    GraphMap,
    LogicalTable,
    ObjectMap,
    PredicateObjectMap,
    Resource,
    SubjectMap
  }

  alias AshR2RML.OBDA

  @g_public "urn:uuid:00000000-0000-4000-8000-000000000001"
  @g_donor "urn:uuid:00000000-0000-4000-8000-000000000002"
  @g_elder "urn:uuid:00000000-0000-4000-8000-000000000003"
  @g_syndicate "urn:uuid:00000000-0000-4000-8000-000000000004"
  @all_graphs [@g_public, @g_donor, @g_elder, @g_syndicate]

  @title_pred "https://schema.org/name"
  @string "http://www.w3.org/2001/XMLSchema#string"
  @base "urn:uuid:"

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.NamedGraphsFourViewsTest.Record
    end
  end

  defmodule Record do
    use Ash.Resource,
      domain: AshR2RML.NamedGraphsFourViewsTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      authorizers: [Ash.Policy.Authorizer]

    ets do
      private?(false)
    end

    multitenancy do
      strategy(:attribute)
      attribute(:tenant_id)
    end

    actions do
      defaults([:read, :destroy, create: [:title, :view]])
    end

    policies do
      policy action_type(:read) do
        authorize_if(expr(view == "urn:uuid:00000000-0000-4000-8000-000000000001"))
        authorize_if(expr(view in ^actor(:views)))
      end
    end

    identities do
      identity(:by_title, [:title], pre_check_with: AshR2RML.NamedGraphsFourViewsTest.Domain)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:title, :string, allow_nil?: false, public?: true)
      attribute(:view, :string, allow_nil?: false, public?: true)
      attribute(:tenant_id, :string, allow_nil?: false, public?: true)
    end
  end

  # view => {title, graph}
  @rows [
    public: {"pub", @g_public},
    donor_cpa: {"donor", @g_donor},
    elder_governance: {"elder", @g_elder},
    private_syndicate: {"syndicate", @g_syndicate}
  ]

  defp actor(views), do: %{views: views}

  defp specs do
    pom = %PredicateObjectMap{
      attribute: :title,
      predicate_iri: @title_pred,
      object_map: %ObjectMap{
        strategy: :column,
        value: "title",
        datatype: %Datatype{ash_type: Ash.Type.String, rdf_datatype: @string}
      }
    }

    mapping = %Resource{
      ash_resource: Record,
      logical_table: %LogicalTable{table_name: "records"},
      subject_map: %SubjectMap{
        strategy: :template,
        value: @base <> "{title}",
        term_type: :iri,
        graph_maps: [%GraphMap{strategy: :column, value: "view"}]
      },
      class_iris: ["https://schema.org/Thing"],
      predicate_object_maps: [pom],
      identities: [[:title]],
      metadata: %{source: :named_graphs_four_views_test}
    }

    [{Record, mapping}]
  end

  defp run(sparql, tenant, views) do
    OBDA.query(specs(), sparql, domain: Domain, tenant: tenant, actor: actor(views))
  end

  defp graph_subjects(%OBDA.Result{bindings: rows}) do
    rows |> Enum.map(&{to_string(&1["g"]), to_string(&1["s"])}) |> Enum.sort()
  end

  defp expected(titles_graphs) do
    titles_graphs |> Enum.map(fn {title, graph} -> {graph, @base <> title} end) |> Enum.sort()
  end

  defp row(view), do: Keyword.fetch!(@rows, view)

  @graph_select "SELECT ?g ?s WHERE { GRAPH ?g { ?s <#{@title_pred}> ?o } }"

  setup do
    for tenant <- ["A", "B"] do
      Record
      |> Ash.read!(tenant: tenant, authorize?: false, domain: Domain)
      |> Enum.each(&Ash.destroy!(&1, tenant: tenant, authorize?: false, domain: Domain))
    end

    for {_view, {title, graph}} <- @rows do
      Record
      |> Ash.Changeset.for_create(:create, %{title: title, view: graph},
        tenant: "A",
        domain: Domain
      )
      |> Ash.create!(authorize?: false, tenant: "A", domain: Domain)
    end

    Record
    |> Ash.Changeset.for_create(:create, %{title: "b-secret", view: @g_syndicate},
      tenant: "B",
      domain: Domain
    )
    |> Ash.create!(authorize?: false, tenant: "B", domain: Domain)

    :ok
  end

  describe "GRAPH ?g visibility per actor" do
    test "an actor with every view sees one subject in each of the four graphs" do
      assert {:ok, result} = run(@graph_select, "A", @all_graphs)

      assert graph_subjects(result) ==
               expected(for {_v, {t, g}} <- @rows, do: {t, g})
    end

    test "donor/CPA actor sees public and donor graphs only" do
      assert {:ok, result} = run(@graph_select, "A", [@g_donor])
      assert graph_subjects(result) == expected([row(:public), row(:donor_cpa)])
    end

    test "elder-governance actor sees public and elder graphs only" do
      assert {:ok, result} = run(@graph_select, "A", [@g_elder])
      assert graph_subjects(result) == expected([row(:public), row(:elder_governance)])
    end

    test "syndicate actor sees public and private-syndicate graphs only" do
      assert {:ok, result} = run(@graph_select, "A", [@g_syndicate])
      assert graph_subjects(result) == expected([row(:public), row(:private_syndicate)])
    end

    test "actor with no views sees only the public graph" do
      assert {:ok, result} = run(@graph_select, "A", [])
      assert graph_subjects(result) == expected([row(:public)])
    end
  end

  describe "unauthorized actor and restricted graphs" do
    test "GRAPH <restricted> yields zero bindings for an unauthorized actor" do
      for graph <- [@g_donor, @g_elder, @g_syndicate] do
        sparql = "SELECT ?s ?p ?o WHERE { GRAPH <#{graph}> { ?s ?p ?o } }"
        assert {:ok, result} = run(sparql, "A", [])
        assert result.bindings == [], "graph #{graph} leaked triples"
      end
    end

    test "GRAPH <restricted> yields triples for the authorized actor (positive control)" do
      sparql = "SELECT ?s ?p ?o WHERE { GRAPH <#{@g_donor}> { ?s ?p ?o } }"

      assert {:ok, result} = run(sparql, "A", [@g_donor])
      assert result.bindings != []

      subjects = result.bindings |> Enum.map(&to_string(&1["s"])) |> Enum.uniq()
      assert subjects == [@base <> "donor"]
    end

    test "a view grant does not cross over to another restricted graph" do
      sparql = "SELECT ?s ?p ?o WHERE { GRAPH <#{@g_syndicate}> { ?s ?p ?o } }"
      assert {:ok, result} = run(sparql, "A", [@g_donor, @g_elder])
      assert result.bindings == []
    end

    test "restricted subjects and values never appear in an unauthorized unrestricted-shape query" do
      sparql = "SELECT ?s ?o WHERE { ?s <#{@title_pred}> ?o }"
      assert {:ok, result} = run(sparql, "A", [])

      objects = result.bindings |> Enum.map(&to_string(&1["o"]))
      refute Enum.any?(objects, &(&1 in ["donor", "elder", "syndicate"]))
      refute inspect(result) =~ "syndicate"
    end
  end

  describe "tenant isolation across graph views" do
    test "tenant B sees only its own row even with every view granted" do
      assert {:ok, result} = run(@graph_select, "B", @all_graphs)
      assert graph_subjects(result) == [{@g_syndicate, @base <> "b-secret"}]
    end

    test "tenant A never sees tenant B's syndicate row" do
      assert {:ok, result} = run(@graph_select, "A", @all_graphs)
      refute Enum.any?(graph_subjects(result), fn {_g, s} -> s == @base <> "b-secret" end)
    end

    test "missing tenant is refused, not read across tenants" do
      assert {:error, error} =
               OBDA.query(specs(), @graph_select, domain: Domain, actor: actor(@all_graphs))

      assert error.code == :REFUSED_MISSING_TENANT
    end
  end
end
