# SPDX-License-Identifier: MIT
defmodule AshR2RML.KnowledgeHook.Control do
  @moduledoc "Deterministic CONSTRUCT-only scheduler. It never performs DO."
  alias AshR2RML.{Compiler, Refusal}
  alias AshR2RML.KnowledgeHook.Scheduler

  @planners [:hddl, :fond, :powl]
  @ceiling MapSet.new([:OBSERVE, :SELECT, :CONSTRUCT])
  defstruct epoch: 0, capacity: 64, queue: :queue.new(), seen: MapSet.new(),
            leases: %{}, providers: %{}, receipts: []

  def new(opts \\ []) do
    %__MODULE__{epoch: Keyword.get(opts, :epoch, 0), capacity: Keyword.get(opts, :capacity, 64),
      providers: Map.new(Keyword.get(opts, :providers, []), fn p ->
        {to_string(get(p, :id)), %{id: to_string(get(p, :id)), alive?: get(p, :alive?, true),
          planners: get(p, :planners, [])}} end)}
  end

  def admit(specs, order) do
    with {:ok, scheduled} <- Scheduler.schedule(specs),
         :ok <- exact_subject(order), :ok <- authority(order), :ok <- bound(order),
         {:ok, planner} <- planner(order), {:ok, provider} <- provider(order, planner) do
      core = %{subject: get(order, :subject_sha256), epoch: get(order, :epoch), role: get(order, :role),
        policy: get(order, :policy), planner: planner, provider: provider, max_steps: get(order, :max_steps),
        specs: Enum.map(scheduled, & &1.spec_sha256)}
      {:ok, Map.merge(core, %{work_order_sha256: Compiler.sha256(core), authority: :UNAUTHORIZED,
        authority_ceiling: :CONSTRUCT, standing: :selected_not_actuated})}
    end
  end

  def enqueue(state, order) do
    id = order.work_order_sha256
    cond do
      MapSet.member?(state.seen, id) -> {:ok, state, receipt(:KNOWN_REPLAY, order, %{})}
      :queue.len(state.queue) >= state.capacity -> {:error, :backpressure, state}
      true -> {:ok, %{state | queue: :queue.in(order, state.queue), seen: MapSet.put(state.seen, id)},
        receipt(:QUEUED, order, %{})}
    end
  end

  def lease(state, provider_id, now) do
    case {Map.get(state.providers, provider_id), :queue.out(state.queue)} do
      {%{alive?: true}, {{:value, order}, rest}} ->
        id = Compiler.sha256({order.work_order_sha256, provider_id, state.epoch, now})
        lease = %{id: id, work_order_sha256: order.work_order_sha256, provider: provider_id,
          epoch: state.epoch, leased_at: now}
        {:ok, %{state | queue: rest, leases: Map.put(state.leases, id, {lease, order})}, lease, order}
      {nil, _} -> {:error, :unknown_provider, state}
      {%{alive?: false}, _} -> {:error, :provider_extinct, state}
      {_, {:empty, _}} -> {:error, :empty, state}
    end
  end

  def complete(state, lease_id, evidence) do
    case Map.get(state.leases, lease_id) do
      nil -> {:error, :unknown_or_stale_lease, state}
      {lease, order} ->
        cond do
          lease.epoch != state.epoch -> {:error, :stale_epoch, state}
          get(evidence, :consequence, :none) != :none -> {:error, :authority_laundering, state}
          get(evidence, :steps, 0) > order.max_steps -> {:error, :construction_bound_exceeded, state}
          true ->
            r = receipt(:CONSTRUCTED, order, %{lease: lease.id, provider: lease.provider,
              evidence_sha256: Compiler.sha256(evidence), requires_brce?: true})
            {:ok, %{state | leases: Map.delete(state.leases, lease_id), receipts: [r | state.receipts]}, r}
        end
    end
  end

  def extinct(state, provider_id) do
    providers = Map.update(state.providers, provider_id, %{id: provider_id, alive?: false},
      &Map.put(&1, :alive?, false))
    {lost, kept} = Enum.split_with(state.leases, fn {_id, {lease, _}} -> lease.provider == provider_id end)
    queue = Enum.reduce(lost, state.queue, fn {_id, {_lease, order}}, q -> :queue.in_r(order, q) end)
    %{state | providers: providers, leases: Map.new(kept), queue: queue, epoch: state.epoch + 1}
  end

  def replay(receipts), do: Enum.sort_by(receipts, &{&1.work_order_sha256, &1.receipt_sha256})

  defp exact_subject(order) do
    v = get(order, :subject_sha256)
    if is_binary(v) and String.match?(v, ~r/^sha256:[0-9a-f]{64}$/), do: :ok,
      else: refuse(:subject, "exact sha256 subject required")
  end
  defp authority(order) do
    if MapSet.subset?(MapSet.new(get(order, :authority, [])), @ceiling), do: :ok,
      else: refuse(:authority, "authority exceeds CONSTRUCT ceiling")
  end
  defp bound(order) do
    n = get(order, :max_steps)
    if is_integer(n) and n > 0 and n <= 10_000, do: :ok, else: refuse(:max_steps, "finite bound required")
  end
  defp planner(order) do
    case Enum.find(@planners, &(&1 in get(order, :planners, @planners))) do
      nil -> refuse(:planner, "no admitted planner")
      p -> {:ok, p}
    end
  end
  defp provider(order, planner) do
    case get(order, :providers, []) |> Enum.filter(&(get(&1, :alive?, true) and planner in get(&1, :planners, [])))
         |> Enum.sort_by(&to_string(get(&1, :id))) |> List.first() do
      nil -> refuse(:provider, "no live provider")
      p -> {:ok, to_string(get(p, :id))}
    end
  end
  defp receipt(status, order, extra) do
    core = Map.merge(%{schema: "ash-r2rml/knowledge-hook-control/v1", status: status,
      work_order_sha256: order.work_order_sha256, consequence: :none, authority: :UNAUTHORIZED}, extra)
    Map.put(core, :receipt_sha256, Compiler.sha256(core))
  end
  defp refuse(subject, msg), do: {:error, Refusal.new(:REFUSED_UNPROVEN_EQUIVALENCE, subject, msg)}
  defp get(map, key, default \\ nil), do: Map.get(map, key, Map.get(map, to_string(key), default))
end
