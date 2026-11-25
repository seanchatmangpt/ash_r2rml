# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OBDAQueryEnvelopeTest do
  @moduledoc """
  Exact-state tests for `AshR2RML.OBDA.query/3`: canonical ordering, stats, digest,
  bounds and telemetry over real `Ash.DataLayer.Ets` rows (public table, since the query
  runs inside `AshR2RML.OBDA.Worker`).
  """
  use ExUnit.Case, async: false

  alias AshR2RML.Mapping.{LogicalTable, ObjectMap, PredicateObjectMap, Resource, SubjectMap}
  alias AshR2RML.OBDA
  alias AshR2RML.OBDA.Result
  alias AshR2RML.Error

  doctest AshR2RML.OBDA.Result

  defmodule Dom do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.OBDAQueryEnvelopeTest.Person
    end
  end

  defmodule Person do
    use Ash.Resource, domain: AshR2RML.OBDAQueryEnvelopeTest.Dom, data_layer: Ash.DataLayer.Ets

    actions do
      defaults [:read, :destroy]

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

  @ex "urn:uuid:"
  @name "https://schema.org/name"

  defp mapping do
    %Resource{
      ash_resource: Person,
      logical_table: %LogicalTable{table_name: "person"},
      subject_map: %SubjectMap{strategy: :template, value: @ex <> "person-{pid}"},
      class_iris: ["https://schema.org/Person"],
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

  defp specs, do: [{Person, mapping()}]

  defp create!(attrs) do
    Person |> Ash.Changeset.for_create(:create, attrs, domain: Dom) |> Ash.create!(domain: Dom)
  end

  @select "SELECT ?name WHERE { ?s <#{@name}> ?name }"

  # The public ETS table is owned by Ash's long-lived TableManager GenServer, started on
  # first access. It is warmed once here and never stopped (`Ets.stop/1` kills the manager
  # asynchronously, which races the next test's table lookup). Rows are cleared per test
  # through the real destroy action.
  setup_all do
    Ash.read!(Person, domain: Dom)
    :ok
  end

  setup do
    Person |> Ash.read!(domain: Dom) |> Ash.bulk_destroy!(:destroy, %{}, domain: Dom)
    :ok
  end

  def forward(event, measurements, metadata, pid), do: send(pid, {:telemetry, event, measurements, metadata})

  test "SELECT returns canonically sorted bindings with exact stats" do
    create!(%{pid: "p2", name: "Bob"})
    create!(%{pid: "p1", name: "Ann"})

    assert {:ok, %Result{} = result} = OBDA.query(specs(), @select, domain: Dom)
    assert result.bindings == [%{"name" => "Ann"}, %{"name" => "Bob"}]
    assert result.triples == []
    assert result.stats.rows_read == 2
    assert result.stats.triples_emitted == 4
    assert result.stats.resources_pruned_by_policy == 0
    assert is_integer(result.stats.duration_us) and result.stats.duration_us >= 0
    assert result.digest =~ ~r/\A[0-9a-f]{64}\z/
  end

  test "digest is deterministic for equal state and changes with data or query" do
    create!(%{pid: "p1", name: "Ann"})

    {:ok, a} = OBDA.query(specs(), @select, domain: Dom)
    {:ok, b} = OBDA.query(specs(), @select, domain: Dom)
    assert a.digest == b.digest

    {:ok, other_query} = OBDA.query(specs(), @select <> " ", domain: Dom)
    refute other_query.digest == a.digest

    create!(%{pid: "p2", name: "Bob"})
    {:ok, c} = OBDA.query(specs(), @select, domain: Dom)
    refute c.digest == a.digest
  end

  test "CONSTRUCT fills triples, sorted, and leaves bindings empty" do
    create!(%{pid: "p1", name: "Ann"})

    sparql = "CONSTRUCT { ?s <#{@name}> ?n } WHERE { ?s <#{@name}> ?n }"
    assert {:ok, result} = OBDA.query(specs(), sparql, domain: Dom)
    assert result.bindings == []

    assert result.triples == [
             %{"subject" => @ex <> "person-p1", "predicate" => @name, "object" => "Ann"}
           ]
  end

  test "max_triples refuses an oversized graph with a typed refusal" do
    create!(%{pid: "p1", name: "Ann"})

    assert {:error, %Error{code: :REFUSED_TRIPLE_LIMIT_EXCEEDED, details: %{limit: 1}}} =
             OBDA.query(specs(), @select, domain: Dom, max_triples: 1)
  end

  test "max_rows refuses an oversized result" do
    create!(%{pid: "p1", name: "Ann"})
    create!(%{pid: "p2", name: "Bob"})

    assert {:error, %Error{code: :REFUSED_RESULT_LIMIT_EXCEEDED}} =
             OBDA.query(specs(), @select, domain: Dom, max_rows: 1)
  end

  test "authorize?: false without allow_unauthorized is refused fail-closed" do
    assert {:error, %Error{}} = OBDA.query(specs(), @select, domain: Dom, authorize?: false)

    assert {:ok, %Result{bindings: []}} =
             OBDA.query(specs(), @select, domain: Dom, authorize?: false, allow_unauthorized: true)
  end

  test "an unmapped source is a typed refusal" do
    assert {:error, %Error{}} = OBDA.query([], @select)
  end

  test "telemetry emits start then stop with result metadata" do
    create!(%{pid: "p1", name: "Ann"})
    id = {__MODULE__, make_ref()}

    :telemetry.attach_many(
      id,
      [
        [:ash_r2rml, :obda, :query, :start],
        [:ash_r2rml, :obda, :query, :stop],
        [:ash_r2rml, :obda, :query, :exception]
      ],
      &__MODULE__.forward/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(id) end)

    assert {:ok, _} = OBDA.query(specs(), @select, domain: Dom)

    assert_received {:telemetry, [:ash_r2rml, :obda, :query, :start], %{system_time: _}, %{sparql_bytes: bytes}}
    assert bytes == byte_size(@select)

    assert_received {:telemetry, [:ash_r2rml, :obda, :query, :stop], %{duration: duration}, %{result: :ok}}
    assert is_integer(duration)
    refute_received {:telemetry, [:ash_r2rml, :obda, :query, :exception], _, _}
  end

  test "stop metadata carries the refusal code" do
    id = {__MODULE__, make_ref()}
    :telemetry.attach(id, [:ash_r2rml, :obda, :query, :stop], &__MODULE__.forward/4, self())
    on_exit(fn -> :telemetry.detach(id) end)

    assert {:error, %Error{}} = OBDA.query([], @select)

    assert_received {:telemetry, [:ash_r2rml, :obda, :query, :stop], _, %{result: :error, code: code}}
    assert code == :REFUSED_UNSUPPORTED_SPARQL_FEATURE
  end
end
