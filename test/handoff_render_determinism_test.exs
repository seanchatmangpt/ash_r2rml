# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.HandoffRenderDeterminismTest.Org do
  use Ash.Resource, domain: nil, data_layer: Ash.DataLayer.Ets, extensions: [AshR2RML.Resource]

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
  end

  r2rml do
    table_name("hrd_orgs")
    class(["http://www.w3.org/ns/org#Organization", "http://xmlns.com/foaf/0.1/Organization"])

    subject do
      template("urn:uuid:{id}")
    end

    property(:name, "http://www.w3.org/2000/01/rdf-schema#label")
    graph("urn:uuid:00000000-0000-4000-8000-000000000001")
  end
end

defmodule AshR2RML.HandoffRenderDeterminismTest.Dept do
  use Ash.Resource, domain: nil, data_layer: Ash.DataLayer.Ets, extensions: [AshR2RML.Resource]

  attributes do
    uuid_primary_key :id
    attribute :title, :string, allow_nil?: false, public?: true
  end

  relationships do
    belongs_to :org, AshR2RML.HandoffRenderDeterminismTest.Org, allow_nil?: false, public?: true
  end

  r2rml do
    table_name("hrd_depts")
    class("http://www.w3.org/ns/org#OrganizationalUnit")

    subject do
      template("urn:uuid:{id}")
    end

    property(:title, "http://purl.org/dc/terms/title")
    reference(:org, "http://www.w3.org/ns/org#unitOf", inverse_predicate: "http://www.w3.org/ns/org#hasUnit")
    graph("urn:uuid:00000000-0000-4000-8000-000000000002")
  end
end

defmodule AshR2RML.HandoffRenderDeterminismTest.Person do
  use Ash.Resource, domain: nil, data_layer: Ash.DataLayer.Ets, extensions: [AshR2RML.Resource]

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
  end

  relationships do
    belongs_to :dept, AshR2RML.HandoffRenderDeterminismTest.Dept, allow_nil?: false, public?: true
  end

  r2rml do
    table_name("hrd_people")
    class("http://xmlns.com/foaf/0.1/Person")

    subject do
      template("urn:uuid:{id}")
    end

    property(:name, "http://xmlns.com/foaf/0.1/name")
    reference(:dept, "http://www.w3.org/ns/org#memberOf")
    graph("urn:uuid:00000000-0000-4000-8000-000000000003")
  end
end

defmodule AshR2RML.HandoffRenderDeterminismTest.Project do
  use Ash.Resource, domain: nil, data_layer: Ash.DataLayer.Ets, extensions: [AshR2RML.Resource]

  attributes do
    uuid_primary_key :id
    attribute :code, :string, allow_nil?: false, public?: true
  end

  relationships do
    belongs_to :org, AshR2RML.HandoffRenderDeterminismTest.Org, allow_nil?: false, public?: true
    belongs_to :lead, AshR2RML.HandoffRenderDeterminismTest.Person, allow_nil?: false, public?: true
  end

  r2rml do
    table_name("hrd_projects")
    class("http://xmlns.com/foaf/0.1/Project")

    subject do
      template("urn:uuid:{id}")
    end

    property(:code, "http://www.w3.org/2004/02/skos/core#notation")
    reference(:org, "http://purl.org/dc/terms/publisher")
    reference(:lead, "http://purl.org/dc/terms/creator")
  end
end

defmodule AshR2RML.HandoffRenderDeterminismTest do
  @moduledoc """
  The R2RML render is byte-identical for every permutation of the resource list
  (4 resources, joins and named graphs) and across repeated runs.
  """

  use ExUnit.Case, async: false

  alias AshR2RML.HandoffRenderDeterminismTest.{Dept, Org, Person, Project}
  alias AshR2RML.Mapping.Bundle

  @modules [Org, Dept, Person, Project]

  defp permutations([]), do: [[]]
  defp permutations(list), do: for(x <- list, rest <- permutations(list -- [x]), do: [x | rest])

  defp headers(ttl) do
    Regex.scan(~r/^<([^>\s]+)> a rr:TriplesMap/m, ttl, capture: :all_but_first)
    |> List.flatten()
  end

  defp reference! do
    assert {:ok, ttl} = AshR2RML.R2RML.render(@modules)
    ttl
  end

  test "reference output carries the joins and graphs the permutations must preserve" do
    ttl = reference!()

    assert ttl =~ "rr:parentTriplesMap"
    assert ttl =~ "rr:joinCondition"
    assert ttl =~ "urn:uuid:00000000-0000-4000-8000-000000000001"
    assert ttl =~ "urn:uuid:00000000-0000-4000-8000-000000000002"
    assert ttl =~ "urn:uuid:00000000-0000-4000-8000-000000000003"
    assert ttl =~ "http://www.w3.org/ns/org#hasUnit"
    assert length(headers(ttl)) >= 4
  end

  test "all 24 permutations of the resource list render byte-identical Turtle" do
    reference = reference!()
    perms = permutations(@modules)
    assert length(perms) == 24

    for perm <- perms do
      assert {:ok, ttl} = AshR2RML.R2RML.render(perm)
      assert ttl == reference
    end
  end

  test "all 24 permutations of compiled Bundle resources render byte-identical Turtle" do
    assert {:ok, %Bundle{resources: resources} = bundle} =
             AshR2RML.Compiler.compile_resources(@modules)

    assert length(resources) == 4
    reference = reference!()

    for perm <- permutations(resources) do
      assert {:ok, ttl} = AshR2RML.R2RML.render(%Bundle{bundle | resources: perm})
      assert ttl == reference
    end
  end

  test "adversarial: triples-map order is independent of input order, so ordering cannot leak" do
    reference = reference!()
    ref_headers = headers(reference)

    inputs = [@modules, Enum.reverse(@modules), rotate(@modules, 1), rotate(@modules, 2)]
    assert length(Enum.uniq(inputs)) == 4

    for input <- inputs do
      assert {:ok, ttl} = AshR2RML.R2RML.render(input)
      assert headers(ttl) == ref_headers
    end

    # Non-vacuity: base maps plus inverse/bridge maps are all present.
    assert length(ref_headers) == 5
  end

  test "repeated renders in one VM are identical" do
    reference = reference!()

    for _ <- 1..10 do
      assert {:ok, ^reference} = AshR2RML.R2RML.render(@modules)
    end
  end

  test "repeated renders in independent processes are identical" do
    reference = reference!()

    results =
      1..6
      |> Enum.map(fn _ -> Task.async(fn -> AshR2RML.R2RML.render(Enum.shuffle(@modules)) end) end)
      |> Enum.map(&Task.await(&1, 5_000))

    assert Enum.all?(results, &(&1 == {:ok, reference}))
  end

  defp rotate(list, n) do
    {head, tail} = Enum.split(list, n)
    tail ++ head
  end
end
