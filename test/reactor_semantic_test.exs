# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.ReactorSemanticTest do
  @moduledoc """
  An `Ash.Reactor` saga over real ETS-backed Ash resources. The virtual RDF view served by
  `AshR2RML.OBDA.InMemory` shows the created triples mid-saga, and after a downstream failure
  triggers Reactor `undo` compensation (destroy) no stale triples remain.
  """

  use ExUnit.Case, async: false

  alias AshR2RML.Mapping.{Datatype, LogicalTable, ObjectMap, PredicateObjectMap, Resource, SubjectMap}
  alias AshR2RML.OBDA.InMemory

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.ReactorSemanticTest.Entry
    end
  end

  defmodule Entry do
    use Ash.Resource,
      domain: AshR2RML.ReactorSemanticTest.Domain,
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(true)
    end

    multitenancy do
      strategy(:attribute)
      attribute(:tenant_id)
    end

    actions do
      defaults([:read, :destroy, create: [:title]])

      destroy :undo_destroy do
        require_atomic?(false)
        argument(:changeset, :struct, allow_nil?: false)
      end
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:title, :string, allow_nil?: false, public?: true)
      attribute(:tenant_id, :string, allow_nil?: false, public?: true)
    end
  end

  @title_pred "https://example.org/title"
  @string "http://www.w3.org/2001/XMLSchema#string"
  @select "SELECT ?s ?t WHERE { ?s <#{@title_pred}> ?t }"

  defp mapping do
    %Resource{
      ash_resource: Entry,
      logical_table: %LogicalTable{table_name: "entries"},
      subject_map: %SubjectMap{
        strategy: :template,
        value: "https://example.org/entries/{title}",
        term_type: :iri
      },
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
      metadata: %{source: :reactor_semantic_test}
    }
  end

  defp subjects(tenant) do
    {:ok, observation} = InMemory.query(Entry, mapping(), @select, domain: Domain, tenant: tenant)
    observation.rows |> Enum.map(&to_string(&1["s"])) |> Enum.sort()
  end

  defmodule Observe do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(arguments, _context, _options) do
      {:ok, observation} =
        InMemory.query(
          AshR2RML.ReactorSemanticTest.Entry,
          arguments.mapping,
          arguments.select,
          domain: AshR2RML.ReactorSemanticTest.Domain,
          tenant: arguments.tenant
        )

      subjects = observation.rows |> Enum.map(&to_string(&1["s"])) |> Enum.sort()
      send(arguments.pid, {:observed, subjects})
      {:ok, subjects}
    end
  end

  defmodule Boom do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(_arguments, _context, _options), do: {:error, :downstream_failure}
  end

  defmodule Saga do
    @moduledoc false
    use Ash.Reactor

    input(:title_a)
    input(:title_b)
    input(:tenant)
    input(:pid)
    input(:mapping)
    input(:select)

    create :create_a, AshR2RML.ReactorSemanticTest.Entry, :create do
      domain(AshR2RML.ReactorSemanticTest.Domain)
      inputs(%{title: input(:title_a)})
      tenant(input(:tenant))
      undo(:always)
      undo_action(:undo_destroy)
    end

    create :create_b, AshR2RML.ReactorSemanticTest.Entry, :create do
      domain(AshR2RML.ReactorSemanticTest.Domain)
      inputs(%{title: input(:title_b)})
      tenant(input(:tenant))
      undo(:always)
      undo_action(:undo_destroy)
      wait_for(:create_a)
    end

    step :observe, AshR2RML.ReactorSemanticTest.Observe do
      argument(:a, result(:create_a))
      argument(:b, result(:create_b))
      argument(:tenant, input(:tenant))
      argument(:pid, input(:pid))
      argument(:mapping, input(:mapping))
      argument(:select, input(:select))
    end

    step :boom, AshR2RML.ReactorSemanticTest.Boom do
      argument(:seen, result(:observe))
    end

    return(:boom)
  end

  setup do
    for tenant <- ["T"] do
      Entry
      |> Ash.read!(tenant: tenant, domain: Domain)
      |> Enum.each(&Ash.destroy!(&1, tenant: tenant, domain: Domain))
    end

    :ok
  end

  test "triples exist mid-saga; undo compensation leaves no stale triples" do
    inputs = %{
      title_a: "alpha",
      title_b: "beta",
      tenant: "T",
      pid: self(),
      mapping: mapping(),
      select: @select
    }

    assert {:error, _errors} = Reactor.run(Saga, inputs, %{}, async?: false)

    assert_received {:observed,
                     [
                       "https://example.org/entries/alpha",
                       "https://example.org/entries/beta"
                     ]}

    assert subjects("T") == []
    assert Ash.read!(Entry, tenant: "T", domain: Domain) == []
  end
end
