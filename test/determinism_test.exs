# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.DeterminismTest.A do
  use Ash.Resource, domain: nil, data_layer: Ash.DataLayer.Ets, extensions: [AshR2RML.Resource]

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
  end

  r2rml do
    table_name("det_a")
    class("http://xmlns.com/foaf/0.1/Person")

    subject do
      template("urn:uuid:{id}")
    end

    property(:name, "http://xmlns.com/foaf/0.1/name")
  end
end

defmodule AshR2RML.DeterminismTest.B do
  use Ash.Resource, domain: nil, data_layer: Ash.DataLayer.Ets, extensions: [AshR2RML.Resource]

  attributes do
    uuid_primary_key :id
    attribute :label, :string, allow_nil?: false, public?: true
  end

  relationships do
    belongs_to :a, AshR2RML.DeterminismTest.A, allow_nil?: false, public?: true
  end

  r2rml do
    table_name("det_b")
    class("https://schema.org/Thing")

    subject do
      template("urn:uuid:{id}")
    end

    property(:label, "http://www.w3.org/2000/01/rdf-schema#label")
    reference(:a, "http://purl.org/dc/terms/isPartOf")
  end
end

defmodule AshR2RML.DeterminismTest.C do
  use Ash.Resource, domain: nil, data_layer: Ash.DataLayer.Ets, extensions: [AshR2RML.Resource]

  attributes do
    uuid_primary_key :id
    attribute :note, :string, allow_nil?: false, public?: true
  end

  relationships do
    belongs_to :b, AshR2RML.DeterminismTest.B, allow_nil?: false, public?: true
  end

  r2rml do
    table_name("det_c")
    class("http://www.w3.org/ns/org#Organization")

    subject do
      template("urn:uuid:{id}")
    end

    property(:note, "http://www.w3.org/2004/02/skos/core#note")
    reference(:b, "http://purl.org/dc/terms/references")
  end
end

defmodule AshR2RML.DeterminismTest do
  @moduledoc """
  Determinism of the R2RML renderer (input order of resources/bundle) and of the in-memory
  OBDA backend (insertion order of rows). Real Ash resources, real ETS, real renderer.
  """

  use ExUnit.Case, async: false

  alias AshR2RML.DeterminismTest.{A, B, C}

  alias AshR2RML.Mapping.{
    Bundle,
    Datatype,
    LogicalTable,
    ObjectMap,
    PredicateObjectMap,
    Resource,
    SubjectMap
  }

  alias AshR2RML.OBDA.InMemory

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.DeterminismTest.Item
    end
  end

  defmodule Item do
    use Ash.Resource,
      domain: AshR2RML.DeterminismTest.Domain,
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(true)
    end

    actions do
      defaults([:read, :destroy, create: [:id, :title]])
    end

    attributes do
      attribute(:id, :string, primary_key?: true, allow_nil?: false, public?: true, writable?: true)
      attribute(:title, :string, allow_nil?: false, public?: true)
    end
  end

  @title_pred "http://purl.org/dc/terms/title"
  @string "http://www.w3.org/2001/XMLSchema#string"

  defp permutations([]), do: [[]]
  defp permutations(list), do: for(x <- list, rest <- permutations(list -- [x]), do: [x | rest])

  defp sha(binary), do: :crypto.hash(:sha256, binary) |> Base.encode16(case: :lower)

  describe "R2RML.render/1" do
    test "every permutation of resource modules renders byte-identical Turtle" do
      assert {:ok, reference} = AshR2RML.R2RML.render([A, B, C])
      assert reference != ""

      for perm <- permutations([A, B, C]) do
        assert {:ok, ttl} = AshR2RML.R2RML.render(perm)
        assert ttl == reference
        assert sha(ttl) == sha(reference)
      end
    end

    test "every permutation of Bundle resources renders byte-identical Turtle" do
      assert {:ok, %Bundle{resources: resources} = bundle} = AshR2RML.Compiler.compile_resources([A, B, C])
      assert length(resources) == 3
      assert {:ok, reference} = AshR2RML.R2RML.render(bundle)

      for perm <- permutations(resources) do
        assert {:ok, ttl} = AshR2RML.R2RML.render(%Bundle{bundle | resources: perm})
        assert ttl == reference
        assert sha(ttl) == sha(reference)
      end
    end

    test "repeated render is identical" do
      renders = for _ <- 1..5, do: AshR2RML.R2RML.render([A, B, C])
      assert [{:ok, first} | rest] = renders
      assert Enum.all?(rest, &(&1 == {:ok, first}))
    end
  end

  describe "InMemory insertion-order independence" do
    @select "SELECT ?s ?t WHERE { ?s <#{@title_pred}> ?t }"

    defp mapping do
      %Resource{
        ash_resource: Item,
        logical_table: %LogicalTable{table_name: "items"},
        subject_map: %SubjectMap{strategy: :template, value: "urn:uuid:{id}", term_type: :iri},
        class_iris: [],
        predicate_object_maps: [
          %PredicateObjectMap{
            attribute: :title,
            predicate_iri: @title_pred,
            object_map: %ObjectMap{
              strategy: :column,
              value: "title",
              datatype: %Datatype{ash_type: Ash.Type.String, rdf_datatype: @string}
            }
          }
        ],
        identities: [[:id]],
        metadata: %{source: :determinism_test}
      }
    end

    defp reset_and_insert(ids) do
      Item
      |> Ash.read!(domain: Domain)
      |> Enum.each(&Ash.destroy!(&1, domain: Domain))

      for id <- ids do
        Item
        |> Ash.Changeset.for_create(:create, %{id: id, title: "title-#{id}"}, domain: Domain)
        |> Ash.create!(domain: Domain)
      end
    end

    # The test sorts rows itself: InMemory does not canonicalize row order (see receipt).
    defp canonical_rows(observation) do
      observation.rows
      |> Enum.map(fn row -> row |> Enum.map(fn {k, v} -> {k, to_string(v)} end) |> Enum.sort() end)
      |> Enum.sort()
    end

    defp triple_set(graph) do
      graph |> RDF.Graph.triples() |> MapSet.new()
    end

    @ids ~w(i01 i02 i03 i04 i05 i06 i07)

    test "rows are the same set under different insertion orders (canonicalized by the test)" do
      orders = [@ids, Enum.reverse(@ids), Enum.shuffle(@ids), Enum.shuffle(@ids)]

      results =
        for order <- orders do
          reset_and_insert(order)
          assert {:ok, obs} = InMemory.query(Item, mapping(), @select, domain: Domain)
          assert length(obs.rows) == length(@ids)
          canonical_rows(obs)
        end

      assert length(Enum.uniq(results)) == 1
    end

    test "materialized graphs are triple-set equal under different insertion orders" do
      reset_and_insert(@ids)
      assert {:ok, g1} = InMemory.materialize(Item, mapping(), domain: Domain)

      reset_and_insert(Enum.reverse(@ids))
      assert {:ok, g2} = InMemory.materialize(Item, mapping(), domain: Domain)

      assert MapSet.size(triple_set(g1)) == length(@ids)
      assert triple_set(g1) == triple_set(g2)
    end

    test "repeated query over unchanged data returns identical rows in identical order" do
      reset_and_insert(@ids)
      assert {:ok, first} = InMemory.query(Item, mapping(), @select, domain: Domain)

      for _ <- 1..3 do
        assert {:ok, again} = InMemory.query(Item, mapping(), @select, domain: Domain)
        assert again.rows == first.rows
      end
    end
  end
end
