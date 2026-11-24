# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OBDAPushdownPreflightTest do
  @moduledoc """
  `AshR2RML.OBDA.query/3` point-lookup pushdown (constant subject IRI reads one row) and
  policy preflight (outsider gets an empty result with `resources_pruned_by_policy >= 1`),
  over real `Ash.DataLayer.Ets` rows.
  """
  use ExUnit.Case, async: false

  alias AshR2RML.Mapping.{LogicalTable, ObjectMap, PredicateObjectMap, Resource, SubjectMap}
  alias AshR2RML.OBDA
  alias AshR2RML.OBDA.Result

  defmodule Dom do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.OBDAPushdownPreflightTest.Person
      resource AshR2RML.OBDAPushdownPreflightTest.Secret
    end
  end

  defmodule Person do
    use Ash.Resource, domain: AshR2RML.OBDAPushdownPreflightTest.Dom, data_layer: Ash.DataLayer.Ets

    actions do
      defaults [:read]

      create :create do
        primary? true
        accept [:pid, :name]
      end
    end

    attributes do
      uuid_primary_key :id
      attribute :pid, :string, public?: true
      attribute :name, :string, public?: true
    end
  end

  defmodule Secret do
    use Ash.Resource,
      domain: AshR2RML.OBDAPushdownPreflightTest.Dom,
      data_layer: Ash.DataLayer.Ets,
      authorizers: [Ash.Policy.Authorizer]

    actions do
      defaults [:read]

      create :create do
        primary? true
        accept [:pid, :name]
      end
    end

    policies do
      policy action_type(:read) do
        authorize_if actor_attribute_equals(:role, :admin)
      end
    end

    attributes do
      uuid_primary_key :id
      attribute :pid, :string, public?: true
      attribute :name, :string, public?: true
    end
  end

  @ex "https://ex.org/"
  @name "https://schema.org/name"

  defp mapping(resource, path) do
    %Resource{
      ash_resource: resource,
      logical_table: %LogicalTable{table_name: path},
      subject_map: %SubjectMap{strategy: :template, value: @ex <> path <> "/{pid}"},
      class_iris: ["https://ex.org/Thing"],
      identities: [[:pid]],
      predicate_object_maps: [
        %PredicateObjectMap{
          attribute: :name,
          predicate_iri: @name,
          object_map: %ObjectMap{strategy: :column, value: "name"}
        }
      ]
    }
  end

  setup do
    Ash.DataLayer.Ets.stop(Person)
    Ash.DataLayer.Ets.stop(Secret)

    on_exit(fn ->
      Ash.DataLayer.Ets.stop(Person)
      Ash.DataLayer.Ets.stop(Secret)
    end)

    :ok
  end

  defp seed!(resource, n) do
    for i <- 1..n do
      resource
      |> Ash.Changeset.for_create(:create, %{pid: "#{i}", name: "n#{i}"}, domain: Dom, authorize?: false)
      |> Ash.create!(domain: Dom, authorize?: false)
    end
  end

  test "constant-subject point lookup reads exactly one row of 50" do
    seed!(Person, 50)
    sparql = "SELECT ?n WHERE { <#{@ex}person/25> <#{@name}> ?n }"

    assert {:ok, %Result{} = result} = OBDA.query([{Person, mapping(Person, "person")}], sparql, domain: Dom)
    assert result.bindings == [%{"n" => "n25"}]
    assert result.stats.rows_read == 1
  end

  test "variable-subject query still reads every row" do
    seed!(Person, 50)
    sparql = "SELECT ?n WHERE { ?s <#{@name}> ?n }"

    assert {:ok, result} = OBDA.query([{Person, mapping(Person, "person")}], sparql, domain: Dom)
    assert result.stats.rows_read == 50
    assert length(result.bindings) == 50
  end

  test "constant_subject/1 only extracts a lone-subject pattern" do
    assert OBDA.constant_subject("SELECT ?n WHERE { <https://a.b/s> <https://a.b/p> ?n }") == "https://a.b/s"
    assert OBDA.constant_subject("SELECT ?n WHERE { <https://a.b/s> <https://a.b/p> ?n . }") == "https://a.b/s"
    assert OBDA.constant_subject("SELECT ?n WHERE { ?s <https://a.b/p> ?n }") == nil

    assert OBDA.constant_subject("SELECT ?n WHERE { <https://a.b/s> <https://a.b/p> ?n . ?x <https://a.b/q> ?n }") ==
             nil

    assert OBDA.constant_subject("SELECT ?n WHERE { <https://a.b/s> <https://a.b/p> ?n OPTIONAL { ?x ?y ?z } }") ==
             nil
  end

  test "outsider on a policy resource gets an empty result, pruned, zero rows read" do
    seed!(Secret, 5)
    sparql = "SELECT ?n WHERE { ?s <#{@name}> ?n }"
    specs = [{Secret, mapping(Secret, "secret")}]

    assert {:ok, %Result{} = outsider} = OBDA.query(specs, sparql, domain: Dom, actor: %{role: :guest})
    assert outsider.bindings == []
    assert outsider.stats.resources_pruned_by_policy >= 1
    assert outsider.stats.rows_read == 0

    assert {:ok, admin} = OBDA.query(specs, sparql, domain: Dom, actor: %{role: :admin})
    assert length(admin.bindings) == 5
    assert admin.stats.resources_pruned_by_policy == 0
  end
end
