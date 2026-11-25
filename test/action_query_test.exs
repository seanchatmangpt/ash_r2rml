# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.ActionQueryTest do
  @moduledoc """
  `AshR2RML.Action.Query` wired as a real generic action in a real Ash domain, reading real
  `Ash.DataLayer.Ets` rows.
  """
  use ExUnit.Case, async: false

  alias AshR2RML.Mapping.{LogicalTable, ObjectMap, PredicateObjectMap, Resource, SubjectMap}

  defmodule Dom do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.ActionQueryTest.Thing
      resource AshR2RML.ActionQueryTest.Gateway
      resource AshR2RML.ActionQueryTest.NoSourceGateway
    end
  end

  defmodule Thing do
    use Ash.Resource, domain: AshR2RML.ActionQueryTest.Dom, data_layer: Ash.DataLayer.Ets

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
    use Ash.Resource, domain: AshR2RML.ActionQueryTest.Dom

    actions do
      action :sparql, :map do
        argument :sparql, :string, allow_nil?: false
        run {AshR2RML.Action.Query, specs_fun: {AshR2RML.ActionQueryTest, :specs, []}}
      end
    end
  end

  defmodule NoSourceGateway do
    use Ash.Resource, domain: AshR2RML.ActionQueryTest.Dom

    actions do
      action :sparql, :map do
        argument :sparql, :string, allow_nil?: false
        run AshR2RML.Action.Query
      end
    end
  end

  @label "https://schema.org/name"

  @doc false
  def specs do
    [
      {Thing,
       %Resource{
         ash_resource: Thing,
         logical_table: %LogicalTable{table_name: "thing"},
         subject_map: %SubjectMap{strategy: :template, value: "https://ex.org/thing/{code}"},
         class_iris: ["https://ex.org/Thing"],
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

  # Table owner is Ash's long-lived TableManager; warm once, never `Ets.stop/1` (async kill
  # races the next lookup). Rows are cleared per test via the real destroy action.
  setup_all do
    Ash.read!(Thing, domain: Dom)
    :ok
  end

  setup do
    Thing |> Ash.read!(domain: Dom) |> Ash.bulk_destroy!(:destroy, %{}, domain: Dom)
    :ok
  end

  defp run(resource, sparql) do
    resource
    |> Ash.ActionInput.for_action(:sparql, %{sparql: sparql}, domain: Dom)
    |> Ash.run_action(domain: Dom)
  end

  test "generic action returns the envelope fields for real rows" do
    for {code, label} <- [{"b", "Beta"}, {"a", "Alpha"}] do
      Thing |> Ash.Changeset.for_create(:create, %{code: code, label: label}, domain: Dom) |> Ash.create!(domain: Dom)
    end

    assert {:ok, result} = run(Gateway, "SELECT ?l WHERE { ?s <#{@label}> ?l }")
    assert result.bindings == [%{"l" => "Alpha"}, %{"l" => "Beta"}]
    assert result.triples == []
    assert result.stats.rows_read == 2
    assert result.digest =~ ~r/\A[0-9a-f]{64}\z/
  end

  test "a missing source option is an error, not a crash" do
    assert {:error, _} = run(NoSourceGateway, "ASK { ?s ?p ?o }")
  end
end
