# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.CapabilityProbeTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Capability
  alias AshR2RML.Mapping.Resource
  alias AshR2RML.QueryBuilder
  alias AshR2RML.QueryBuilder.Plan
  alias AshR2RML.Test.MinimalProbeResource

  defmodule Dom do
    use Ash.Domain, validate_config_inclusion?: false
  end

  defmodule EtsThing do
    use Ash.Resource, domain: nil, data_layer: Ash.DataLayer.Ets

    actions do
      defaults [:read]
    end

    attributes do
      uuid_primary_key :id
      attribute :name, :string, public?: true
    end
  end

  defmodule SimpleThing do
    use Ash.Resource, domain: nil

    attributes do
      uuid_primary_key :id
      attribute :name, :string, public?: true
    end
  end

  @keys [:filter, :sort, :limit, :offset, :join, :multitenancy, :transact]

  test "ETS supports pushdown but not transactions" do
    caps = Capability.probe(EtsThing)
    assert Map.keys(caps) |> Enum.sort() == Enum.sort(@keys)
    assert %{filter: true, sort: true, limit: true, offset: true, multitenancy: true, transact: false} = caps
  end

  test "Simple supports sort/limit/offset/filter and multitenancy, no join, no transact" do
    assert %{filter: true, sort: true, limit: true, offset: true, join: false, multitenancy: true, transact: false} =
             Capability.probe(SimpleThing)
  end

  test "minimal layer reports every pushdown feature false" do
    assert Capability.probe(MinimalProbeResource) ==
             Map.new(@keys, &{&1, false})
  end

  test "bytewise string order allowlist: ETS yes, Simple and minimal no" do
    assert Capability.bytewise_string_order?(EtsThing)
    refute Capability.bytewise_string_order?(SimpleThing)
    refute Capability.bytewise_string_order?(MinimalProbeResource)
  end

  describe "QueryBuilder over capabilities" do
    defp mapping(resource) do
      %Resource{
        ash_resource: resource,
        logical_table: %AshR2RML.Mapping.LogicalTable{table_name: "t"},
        subject_map: %AshR2RML.Mapping.SubjectMap{strategy: :template, value: "urn:uuid:{id}"}
      }
    end

    defp plan do
      %Plan{
        needed_attributes: [:name],
        filter: {:and, [{:not_nil, :name, nil}, {:eq, :name, "a"}]},
        sort: [name: :asc],
        offset: 2,
        limit: 5
      }
    end

    test "capable layer receives filter, sort, offset and limit" do
      query = QueryBuilder.build_ash_query(mapping(EtsThing), plan(), domain: Dom)
      assert %Ash.Query{} = query
      assert query.filter != nil
      assert query.sort != []
      assert query.offset == 2
      assert query.limit == 5
    end

    test "layer without pushdown is read plainly and never raises" do
      query = QueryBuilder.build_ash_query(mapping(MinimalProbeResource), plan(), domain: Dom)
      assert %Ash.Query{} = query
      assert query.filter == nil
      assert query.sort == []
      assert query.limit == nil
      assert query.offset in [nil, 0]
    end
  end
end
