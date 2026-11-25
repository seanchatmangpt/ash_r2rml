# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RedActionQueryTest do
  @moduledoc """
  H29: `Action.Query` must not auto-grant `allow_unauthorized` and must validate options in init/1.
  """
  use ExUnit.Case, async: false

  alias AshR2RML.Action.Query
  alias AshR2RML.Mapping.{LogicalTable, ObjectMap, PredicateObjectMap, Resource, SubjectMap}

  defmodule Dom do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.RedActionQueryTest.Thing
      resource AshR2RML.RedActionQueryTest.Gateway
    end
  end

  defmodule Thing do
    use Ash.Resource, domain: AshR2RML.RedActionQueryTest.Dom, data_layer: Ash.DataLayer.Ets

    actions do
      defaults [:read, :destroy]

      create :create do
        primary? true
        accept [:code, :label]
      end
    end

    attributes do
      uuid_primary_key :id
      attribute :code, :string, public?: true
      attribute :label, :string, public?: true
    end
  end

  defmodule Gateway do
    use Ash.Resource, domain: AshR2RML.RedActionQueryTest.Dom

    actions do
      action :sparql, :map do
        argument :sparql, :string, allow_nil?: false
        run {AshR2RML.Action.Query, specs_fun: {AshR2RML.RedActionQueryTest, :specs, []}}
      end
    end
  end

  @label "http://schema.org/name"

  @doc false
  def specs do
    [
      {Thing,
       %Resource{
         ash_resource: Thing,
         logical_table: %LogicalTable{table_name: "thing"},
         subject_map: %SubjectMap{strategy: :template, value: "urn:uuid:{code}"},
         class_iris: ["http://schema.org/Thing"],
         identities: [[:code]],
         predicate_object_maps: [
           %PredicateObjectMap{
             attribute: :label,
             predicate_iri: @label,
             object_map: %ObjectMap{strategy: :column, value: "label"}
           }
         ]
       }}
    ]
  end

  setup_all do
    Ash.read!(Thing, domain: Dom)
    :ok
  end

  setup do
    Thing |> Ash.read!(domain: Dom) |> Ash.bulk_destroy!(:destroy, %{}, domain: Dom)
    :ok
  end

  test "H29 authorize?: false without action-level allow_unauthorized opt-in is refused" do
    Thing
    |> Ash.Changeset.for_create(:create, %{code: "a", label: "Alpha"}, domain: Dom)
    |> Ash.create!(domain: Dom)

    result =
      Gateway
      |> Ash.ActionInput.for_action(:sparql, %{sparql: "SELECT ?l WHERE { ?s <#{@label}> ?l }"}, domain: Dom)
      |> Ash.run_action(domain: Dom, authorize?: false)

    assert {:error, _} = result
  end

  test "H29 init/1 without any source option is an error" do
    assert {:error, _} = Query.init([])
    assert {:error, _} = Query.init(max_rows: 10)
  end

  test "H29 init/1 rejects non-positive-integer bounds" do
    for key <- [:max_rows, :max_triples, :timeout_ms], bad <- [0, -1, "10", 1.5] do
      assert {:error, _} = Query.init([{:resources, [Thing]}, {key, bad}])
    end
  end
end
