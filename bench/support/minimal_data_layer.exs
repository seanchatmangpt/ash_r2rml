# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Minimal in-repo custom Ash.DataLayer for the bench/stress custom layer.
#
# Required callbacks only: can?/2, resource_to_query/2, run_query/2 (plus limit/3, because
# AshR2RML.OBDA.InMemory unconditionally calls Ash.Query.limit(max_rows + 1) and a data layer that
# cannot limit turns every read into an invalid query). Capabilities: :read and :limit are true;
# :filter, :sort, :offset, :transact, :multitenancy and everything else are false, so filter/sort
# pushdown is impossible and must fall back to the full read.
#
# Rows live in a per-resource Agent. A fault injector makes every k-th run_query call return
# {:error, :backend_unavailable} (deterministic, counter held in the same Agent). An optional
# slow_ms makes run_query block in the CALLER (a genuinely slow backend, the stressor itself, not
# a synchronization step).

defmodule Bench.MinimalDataLayer do
  @moduledoc false

  use Spark.Dsl.Extension, transformers: [], sections: []

  @behaviour Ash.DataLayer

  defmodule Query do
    @moduledoc false
    defstruct [:resource, :domain, :limit]
  end

  # -- Ash.DataLayer callbacks -------------------------------------------------

  @impl true
  def can?(_resource, :read), do: true
  def can?(_resource, :limit), do: true
  def can?(_resource, _feature), do: false

  @impl true
  def resource_to_query(resource, domain), do: %Query{resource: resource, domain: domain}

  @impl true
  def limit(%Query{} = query, limit, _resource), do: {:ok, %{query | limit: limit}}

  @impl true
  def run_query(%Query{resource: resource, limit: limit}, _central_resource) do
    {decision, rows, slow_ms} =
      Agent.get_and_update(store_name(resource), fn st ->
        calls = st.calls + 1
        fault? = is_integer(st.fault_every) and st.fault_every > 0 and rem(calls, st.fault_every) == 0
        st = %{st | calls: calls, faults: st.faults + if(fault?, do: 1, else: 0)}
        {{if(fault?, do: :fault, else: :ok), st.rows, st.slow_ms}, st}
      end)

    # SLEEP-CLASS: SCHEDULING (bench stressor: a real slow backend, never used as synchronization)
    if slow_ms > 0, do: Process.sleep(slow_ms)

    case decision do
      :fault -> {:error, :backend_unavailable}
      :ok -> {:ok, if(is_integer(limit), do: Enum.take(rows, limit), else: rows)}
    end
  end

  # -- store API ---------------------------------------------------------------

  @doc "Registered Agent name for a resource's store."
  def store_name(resource), do: Module.concat(resource, MinimalStore)

  @doc "Starts (replacing any prior) store for `resource` seeded with `rows` (attribute maps)."
  def start_store(resource, rows \\ []) do
    stop_store(resource)

    {:ok, pid} =
      Agent.start_link(
        fn ->
          %{rows: load(resource, rows), calls: 0, faults: 0, fault_every: nil, slow_ms: 0}
        end,
        name: store_name(resource)
      )

    {:ok, pid}
  end

  @doc "Stops the store if running."
  def stop_store(resource) do
    case Process.whereis(store_name(resource)) do
      nil ->
        :ok

      pid ->
        ref = Process.monitor(pid)
        Process.unlink(pid)
        Process.exit(pid, :shutdown)

        receive do
          {:DOWN, ^ref, :process, ^pid, _} -> :ok
        after
          5_000 -> :ok
        end
    end
  end

  @doc "Replaces the stored rows (attribute maps) and returns the previous loaded rows."
  def put_rows(resource, rows) do
    new = load(resource, rows)
    Agent.get_and_update(store_name(resource), fn st -> {st.rows, %{st | rows: new}} end)
  end

  @doc "Restores loaded records previously returned by `put_rows/2`."
  def restore_rows(resource, loaded) do
    Agent.update(store_name(resource), fn st -> %{st | rows: loaded} end)
  end

  @doc "Sets `:fault_every` (nil disables) and/or `:slow_ms`; resets the call/fault counters."
  def configure(resource, opts) when is_list(opts) do
    Agent.update(store_name(resource), fn st ->
      %{
        st
        | fault_every: Keyword.get(opts, :fault_every, st.fault_every),
          slow_ms: Keyword.get(opts, :slow_ms, st.slow_ms),
          calls: 0,
          faults: 0
      }
    end)
  end

  @doc "Clears fault injection and slowness."
  def clear(resource), do: configure(resource, fault_every: nil, slow_ms: 0)

  @doc "run_query call and injected-fault counts since the last `configure/2`."
  def stats(resource) do
    Agent.get(store_name(resource), fn st -> %{calls: st.calls, faults: st.faults} end)
  end

  @doc "Row count currently stored."
  def row_count(resource), do: Agent.get(store_name(resource), fn st -> length(st.rows) end)

  defp load(resource, rows) do
    Enum.map(rows, fn
      %{__struct__: _} = record ->
        record

      attrs when is_map(attrs) ->
        record = struct(resource, attrs)
        %{record | __meta__: %Ecto.Schema.Metadata{state: :loaded, schema: resource}}
    end)
  end
end

defmodule Bench.MinimalDataLayer.Domain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource Bench.MinimalDataLayer.Person
  end
end

defmodule Bench.MinimalDataLayer.Person do
  @moduledoc false
  use Ash.Resource,
    domain: Bench.MinimalDataLayer.Domain,
    data_layer: Bench.MinimalDataLayer,
    extensions: [AshR2RML]

  r2rml do
    class_iri("https://ex.org/Person")
    subject_template("https://ex.org/person/{pid}")
    table_name("bench_people")

    attribute_mappings([
      {:name, "https://schema.org/name"},
      {:age, "https://schema.org/age"}
    ])
  end

  actions do
    defaults [:read]
  end

  attributes do
    attribute :pid, :string, primary_key?: true, allow_nil?: false, public?: true
    attribute :name, :string, public?: true
    attribute :age, :integer, public?: true
  end
end
