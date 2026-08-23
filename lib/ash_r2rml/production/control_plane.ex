# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Production.SLO do
  @moduledoc "Pure SLO, capacity and error-budget calculations."

  @spec capacity(map(), keyword()) :: map()
  def capacity(workload, opts \\ []) when is_map(workload) do
    arrival_rate = number(workload, :arrival_rate_per_second, 0.0)
    service_time_ms = number(workload, :service_time_ms, 0.0)
    headroom = Keyword.get(opts, :headroom, 1.5)
    per_replica = Keyword.get(opts, :max_inflight_per_replica, 1_000)

    concurrency = Float.ceil(arrival_rate * (service_time_ms / 1_000.0) * headroom) |> trunc()
    replicas = max(1, ceil_div(max(concurrency, 1), per_replica))

    %{
      arrival_rate_per_second: arrival_rate,
      service_time_ms: service_time_ms,
      headroom: headroom,
      target_concurrency: concurrency,
      max_inflight_per_replica: per_replica,
      minimum_replicas: replicas,
      little_law_identity: :lambda_times_w
    }
  end

  @spec evaluate(map(), map()) :: map()
  def evaluate(observations, objectives) when is_map(observations) and is_map(objectives) do
    checks = [
      {:p99_cold_path_ms, :max},
      {:queue_budget_ms, :max},
      {:availability_percent, :min},
      {:concurrent_operations, :min}
    ]

    results =
      Enum.map(checks, fn {key, direction} ->
        observed = fetch(observations, key, nil)
        target = target_for(objectives, key)
        {key, compare(observed, target, direction)}
      end)

    %{
      status: if(Enum.all?(results, fn {_key, result} -> result == :PASS end), do: :ALIVE, else: :PARTIAL_ALIVE),
      results: Map.new(results)
    }
  end

  @spec error_budget(map(), map()) :: map()
  def error_budget(observation, objective) do
    window_seconds = number(observation, :window_seconds, 0.0)
    failed_seconds = number(observation, :failed_seconds, 0.0)
    target = number(objective, :availability_percent, 99.99)
    allowed_fraction = max(0.0, 1.0 - target / 100.0)
    allowed_seconds = window_seconds * allowed_fraction
    consumed = if allowed_seconds > 0, do: failed_seconds / allowed_seconds, else: :infinity

    %{
      allowed_seconds: allowed_seconds,
      failed_seconds: failed_seconds,
      consumed_ratio: consumed,
      status: burn_status(consumed)
    }
  end

  defp target_for(objectives, :concurrent_operations), do: fetch(objectives, :min_concurrent_operations, nil)
  defp target_for(objectives, key), do: fetch(objectives, key, nil)
  defp compare(nil, _target, _direction), do: :UNKNOWN
  defp compare(_observed, nil, _direction), do: :UNKNOWN
  defp compare(observed, target, :max) when observed <= target, do: :PASS
  defp compare(_observed, _target, :max), do: :FAIL
  defp compare(observed, target, :min) when observed >= target, do: :PASS
  defp compare(_observed, _target, :min), do: :FAIL
  defp burn_status(:infinity), do: :BLOCKED
  defp burn_status(value) when value <= 1.0, do: :HEALTHY
  defp burn_status(value) when value <= 2.0, do: :WARNING
  defp burn_status(_value), do: :BURNING
  defp ceil_div(a, b), do: div(a + b - 1, b)
  defp number(map, key, default), do: fetch(map, key, default) * 1.0
  defp fetch(map, key, default), do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
end

defmodule AshR2RML.Production.Workload do
  @moduledoc "Typed bounded workload intent; construction does not execute work."

  defstruct [
    :id,
    :tenant_id,
    :semantic_subject_sha256,
    :mode,
    :residency,
    :idempotency_key,
    :deadline_ms,
    required_capabilities: [],
    metadata: %{}
  ]

  @type t :: %__MODULE__{}
  @modes [:read, :construct, :do]
  @residencies [:global, :regional, :country_bound]

  @spec new(map()) :: {:ok, t()} | {:error, map()}
  def new(attrs) when is_map(attrs) do
    intent = %__MODULE__{
      id: fetch(attrs, :id, nil),
      tenant_id: fetch(attrs, :tenant_id, nil),
      semantic_subject_sha256: fetch(attrs, :semantic_subject_sha256, nil),
      mode: fetch(attrs, :mode, :read),
      residency: fetch(attrs, :residency, :regional),
      idempotency_key: fetch(attrs, :idempotency_key, nil),
      deadline_ms: fetch(attrs, :deadline_ms, 30_000),
      required_capabilities: fetch(attrs, :required_capabilities, []),
      metadata: fetch(attrs, :metadata, %{})
    }

    missing =
      [:id, :tenant_id, :semantic_subject_sha256]
      |> Enum.filter(&(not present?(Map.get(intent, &1))))

    cond do
      missing != [] -> {:error, refusal(:REFUSED_WORKLOAD_IDENTITY, %{missing: missing})}
      intent.mode not in @modes -> {:error, refusal(:REFUSED_WORKLOAD_MODE, %{mode: intent.mode})}
      intent.residency not in @residencies -> {:error, refusal(:REFUSED_WORKLOAD_RESIDENCY, %{residency: intent.residency})}
      intent.mode == :do and not present?(intent.idempotency_key) -> {:error, refusal(:REFUSED_DO_WITHOUT_IDEMPOTENCY_KEY)}
      not is_integer(intent.deadline_ms) or intent.deadline_ms <= 0 -> {:error, refusal(:REFUSED_WORKLOAD_DEADLINE)}
      true -> {:ok, intent}
    end
  end

  defp refusal(code, evidence \\ %{}), do: %{code: code, evidence: evidence}
  defp present?(value), do: is_binary(value) and byte_size(value) > 0
  defp fetch(map, key, default), do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
end

defmodule AshR2RML.Production.Quota do
  @moduledoc "Hierarchical admission quota; unknown usage fails closed."

  defstruct [:id, :scope, :max_inflight, :max_rps, :current_inflight, :current_rps]
  @type t :: %__MODULE__{}

  @spec admit([t()], pos_integer()) :: {:ok, map()} | {:error, map()}
  def admit(quotas, cost \\ 1) when is_list(quotas) and is_integer(cost) and cost > 0 do
    unknown = Enum.filter(quotas, &(not is_number(&1.current_inflight) or not is_number(&1.current_rps)))

    exceeded =
      Enum.filter(quotas, fn quota ->
        unknown? = quota in unknown
        not unknown? and
          ((quota.max_inflight && quota.current_inflight + cost > quota.max_inflight) or
             (quota.max_rps && quota.current_rps + cost > quota.max_rps))
      end)

    cond do
      unknown != [] -> {:error, %{code: :REFUSED_QUOTA_STATE_UNKNOWN, scopes: Enum.map(unknown, & &1.id)}}
      exceeded != [] -> {:error, %{code: :REFUSED_QUOTA_EXCEEDED, scopes: Enum.map(exceeded, & &1.id)}}
      true -> {:ok, %{status: :ADMITTED, scopes: Enum.map(quotas, & &1.id), cost: cost}}
    end
  end
end

defmodule AshR2RML.Production.Router do
  @moduledoc "Deterministic residency-aware rendezvous routing. No workload execution occurs here."

  alias AshR2RML.Production.Workload

  defmodule Cell do
    @moduledoc "One routable failure-isolation cell."
    defstruct [:id, :region, :country, :status, capabilities: [], metadata: %{}]
    @type t :: %__MODULE__{}
  end

  @spec cells([String.t()], pos_integer()) :: [Cell.t()]
  def cells(regions, cells_per_region \\ 3) when is_list(regions) and is_integer(cells_per_region) and cells_per_region > 0 do
    for region <- Enum.sort(regions), ordinal <- 1..cells_per_region do
      %Cell{
        id: "#{region}-c#{ordinal}",
        region: region,
        country: country_for(region),
        status: :healthy,
        capabilities: [:semantic_runtime, :obda, :telemetry]
      }
    end
  end

  @spec route(Workload.t(), [Cell.t()], keyword()) :: {:ok, map()} | {:error, map()}
  def route(%Workload{} = workload, cells, opts \\ []) when is_list(cells) do
    region = Keyword.get(opts, :region)
    country = Keyword.get(opts, :country)

    eligible =
      cells
      |> Enum.filter(&(&1.status == :healthy))
      |> Enum.filter(&residency_allowed?(&1, workload, region, country))
      |> Enum.filter(&capabilities_allowed?(&1, workload.required_capabilities))

    case eligible do
      [] ->
        {:error,
         %{
           code: :REFUSED_NO_ELIGIBLE_CELL,
           workload_id: workload.id,
           residency: workload.residency,
           requested_region: region,
           requested_country: country
         }}

      candidates ->
        key = "#{workload.tenant_id}:#{workload.semantic_subject_sha256}:#{workload.id}"
        selected = Enum.max_by(candidates, &rendezvous_score(key, &1.id))

        {:ok,
         %{
           status: :ROUTED,
           workload_id: workload.id,
           cell_id: selected.id,
           region: selected.region,
           route_sha256: hash("#{key}:#{selected.id}"),
           do_authority: if(workload.mode == :do, do: :brce_required, else: :none)
         }}
    end
  end

  defp residency_allowed?(cell, workload, region, country) do
    case workload.residency do
      :global -> true
      :regional -> is_binary(region) and cell.region == region
      :country_bound -> is_binary(country) and cell.country == country
    end
  end

  defp capabilities_allowed?(cell, required) do
    Enum.all?(required, &(&1 in cell.capabilities))
  end

  defp rendezvous_score(key, cell_id) do
    :crypto.hash(:sha256, key <> ":" <> cell_id) |> :binary.decode_unsigned()
  end

  defp country_for(region) do
    cond do
      String.starts_with?(region, "us-") -> "US"
      String.starts_with?(region, "eu-") -> "EU"
      String.starts_with?(region, "ca-") -> "CA"
      String.starts_with?(region, "ap-") -> "APAC"
      true -> "UNKNOWN"
    end
  end

  defp hash(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
end
