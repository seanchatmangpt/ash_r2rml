# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

AshR2RML.DataLayerContract.exclude_postgres_by_default!()

defmodule AshR2RML.OBDAQueryLayersThroughWorker.SimpleRead do
  @moduledoc false
  use Ash.Resource.ManualRead

  @impl true
  def read(query, _data_layer_query, _opts, _context) do
    rows = Application.get_env(:ash_r2rml, :obda_worker_layers_simple_rows, [])

    {:ok, for({pid, name, age} <- rows, do: struct(query.resource, pid: pid, name: name, age: age))}
  end
end

alias AshR2RML.CrossLayerEquivalenceAll.Fixture

require Fixture

Fixture.define AshR2RML.OBDAQueryLayersThroughWorker.PublicEts, Ash.DataLayer.Ets, [] do
  ets do
    private? false
  end
end

Fixture.define AshR2RML.OBDAQueryLayersThroughWorker.PrivateEts, Ash.DataLayer.Ets, [] do
  ets do
    private? true
  end
end

Fixture.define AshR2RML.OBDAQueryLayersThroughWorker.Simple,
               Ash.DataLayer.Simple,
               manual: AshR2RML.OBDAQueryLayersThroughWorker.SimpleRead do
end

Fixture.define AshR2RML.OBDAQueryLayersThroughWorker.Mnesia, Ash.DataLayer.Mnesia, [] do
end

if Code.ensure_loaded?(AshCsv.DataLayer) do
  Fixture.define AshR2RML.OBDAQueryLayersThroughWorker.Csv, AshCsv.DataLayer, [] do
    csv do
      file(Path.join(System.tmp_dir!(), "ash_r2rml_obda_worker_layers_#{System.unique_integer([:positive])}.csv"))
      create?(true)
      header?(true)
      columns([:pid, :name, :age])
    end
  end
end

if Code.ensure_loaded?(AshCubDB.DataLayer) do
  Fixture.define AshR2RML.OBDAQueryLayersThroughWorker.Cub, AshCubDB.DataLayer, [] do
    cubdb do
      directory(Path.join(System.tmp_dir!(), "ash_r2rml_obda_worker_cub_#{System.unique_integer([:positive])}"))
    end
  end
end

defmodule AshR2RML.OBDAQueryLayersThroughWorkerTest do
  @moduledoc """
  `AshR2RML.OBDA.query/3` runs its reads inside a spawned `AshR2RML.OBDA.Worker` process. The
  InMemory-direct suites never cross that process boundary; these tests seed real rows into each
  data layer and read them back through `OBDA.query/3`, asserting the exact subjects and values.
  """
  use ExUnit.Case, async: false

  alias AshR2RML.OBDAQueryLayersThroughWorker, as: L

  @sparql "SELECT ?s ?n ?a WHERE { ?s <https://schema.org/name> ?n ; <https://schema.org/age> ?a }"
  @people [{"w1", "Ada", 36}, {"w2", "Grace", 45}, {"w3", "Edsger", 72}]

  @expected [
    {"https://ex.org/person/w1", "Ada", "36"},
    {"https://ex.org/person/w2", "Grace", "45"},
    {"https://ex.org/person/w3", "Edsger", "72"}
  ]

  defp seed!(layer) do
    resource = Module.concat(layer, Person)
    domain = Module.concat(layer, Domain)

    for {pid, name, age} <- @people do
      resource
      |> Ash.Changeset.for_create(:create, %{pid: pid, name: name, age: age}, domain: domain)
      |> Ash.create!(domain: domain, authorize?: false)
    end

    :ok
  end

  defp query(layer) do
    resource = Module.concat(layer, Person)
    domain = Module.concat(layer, Domain)
    mapping = AshR2RML.Resource.Info.mapping!(resource)

    AshR2RML.OBDA.query([{resource, mapping}], @sparql,
      domain: domain,
      authorize?: false,
      allow_unauthorized: true
    )
  end

  defp triples(%AshR2RML.OBDA.Result{bindings: rows}) do
    rows
    |> Enum.map(&{to_string(&1["s"]), to_string(&1["n"]), to_string(&1["a"])})
    |> Enum.sort()
  end

  test "public ETS rows come back through the worker" do
    seed!(L.PublicEts)

    assert {:ok, result} = query(L.PublicEts)
    assert triples(result) == @expected
    assert result.stats.rows_read == 3
  end

  test "private ETS is refused with REFUSED_PRIVATE_DATA_LAYER" do
    assert {:error, error} = query(L.PrivateEts)
    assert error.code == :REFUSED_PRIVATE_DATA_LAYER
  end

  test "Simple (manual read) rows come back through the worker" do
    key = :obda_worker_layers_simple_rows
    previous = Application.fetch_env(:ash_r2rml, key)

    on_exit(fn ->
      case previous do
        {:ok, v} -> Application.put_env(:ash_r2rml, key, v)
        :error -> Application.delete_env(:ash_r2rml, key)
      end
    end)

    Application.put_env(:ash_r2rml, key, @people)

    assert {:ok, result} = query(L.Simple)
    assert triples(result) == @expected
  end

  if Code.ensure_loaded?(AshCsv.DataLayer) do
    test "AshCsv rows come back through the worker" do
      seed!(L.Csv)

      assert {:ok, result} = query(L.Csv)
      assert triples(result) == @expected
    end
  end

  if Code.ensure_loaded?(AshCubDB.DataLayer) do
    test "AshCubDB rows come back through the worker" do
      seed!(L.Cub)

      assert {:ok, result} = query(L.Cub)
      assert triples(result) == @expected
    end
  end

  describe "Ash.DataLayer.Mnesia" do
    setup do
      dir = Path.join(System.tmp_dir!(), "ash_r2rml_obda_worker_mnesia_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      previous = Application.fetch_env(:mnesia, :dir)

      :mnesia.stop()
      Application.put_env(:mnesia, :dir, String.to_charlist(dir))
      :ok = :mnesia.create_schema([node()])
      :ok = :mnesia.start()

      on_exit(fn ->
        :mnesia.stop()

        case previous do
          {:ok, v} -> Application.put_env(:mnesia, :dir, v)
          :error -> Application.delete_env(:mnesia, :dir)
        end

        File.rm_rf(dir)
      end)

      :ok
    end

    test "Mnesia rows come back through the worker" do
      Ash.DataLayer.Mnesia.start(L.Mnesia.Domain)
      :ok = :mnesia.wait_for_tables([L.Mnesia.Person], 5_000)
      seed!(L.Mnesia)

      assert {:ok, result} = query(L.Mnesia)
      assert triples(result) == @expected
    end
  end
end
