# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Fortune5.SLO do
  @moduledoc """
  Pure SLO, capacity and error-budget calculus.

  These functions manufacture targets and admission decisions only. They do not
  claim observed performance. Runtime promotion requires externally supplied
  measurements bound to the exact candidate/environment identity.
  """

  defmodule Objective do
    @moduledoc "One bounded service objective."
    @enforce_keys [:name, :indicator, :target]
    defstruct [:name, :indicator, :target, :window_ms, :unit, :criticality, metadata: %{}]
    @type t :: %__MODULE__{}
  end

  defmodule Capacity do
    @moduledoc "Derived capacity target for one admitted workload model."
    defstruct [
      :required_concurrency,
      :required_workers,
      :required_partitions,
      :headroom_fraction,
      :target_utilization,
      :receipt_sha256,
      assumptions: %{},
      refusals: []
    ]

    @type t :: %__MODULE__{}
  end

  @default_objectives [
    %Objective{name: :availability, indicator: :successful_requests, target: 99.99, window_ms: 30 * 24 * 60 * 60 * 1_000, unit: :percent, criticality: :critical},
    %Objective{name: :p50_latency, indicator: :request_latency_ms, target: 50, window_ms: 5 * 60 * 1_000, unit: :millisecond, criticality: :medium},
    %Objective{name: :p95_latency, indicator: :request_latency_ms, target: 200, window_ms: 5 * 60 * 1_000, unit: :millisecond, criticality: :high},
    %Objective{name: :p99_latency, indicator: :request_latency_ms, target: 500, window_ms: 5 * 60 * 1_000, unit: :millisecond, criticality: :critical},
    %Objective{name: :queue_p99, indicator: :queue_latency_ms, target: 50, window_ms: 5 * 60 * 1_000, unit: :millisecond, criticality: :critical},
    %Objective{name: :refusal_precision, indicator: :typed_refusal_ratio, target: 100.0, window_ms: 60 * 60 * 1_000, unit: :percent, criticality: :critical},
    %Objective{name: :receipt_coverage, indicator: :do_receipt_ratio, target: 100.0, window_ms: 60 * 60 * 1_000, unit: :percent, criticality: :critical},
    %Objective{name: :replay_match, indicator: :replay_match_ratio, target: 100.0, window_ms: 24 * 60 * 60 * 1_000, unit: :percent, criticality: :critical}
  ]

  def objectives, do: @default_objectives

  @doc "Calculate downtime budget for an availability target."
  def downtime_budget_ms(target_percent, window_ms)
      when is_number(target_percent) and target_percent >= 0 and target_percent <= 100 and
             is_integer(window_ms) and window_ms > 0 do
    trunc(window_ms * (1.0 - target_percent / 100.0))
  end

  @doc "Calculate multi-window burn rate from consumed error budget."
  def burn_rate(consumed_error_ms, elapsed_ms, target_percent)
      when is_number(consumed_error_ms) and consumed_error_ms >= 0 and is_integer(elapsed_ms) and
             elapsed_ms > 0 do
    allowed = downtime_budget_ms(target_percent, elapsed_ms)
    if allowed == 0, do: if(consumed_error_ms == 0, do: 0.0, else: :infinity), else: consumed_error_ms / allowed
  end

  @doc "Classify an error-budget burn without promoting it to an alert delivery action."
  def classify_burn(rate) when is_number(rate) do
    cond do
      rate >= 14.4 -> :page
      rate >= 6.0 -> :ticket
      rate >= 2.0 -> :investigate
      rate >= 1.0 -> :budget_exhausting
      true -> :within_budget
    end
  end

  def classify_burn(:infinity), do: :page

  @doc "Derive required concurrency using Little's Law plus bounded headroom."
  def capacity(workload, opts \\ []) when is_map(workload) do
    arrival_rate = number(workload, :arrival_rate_per_second)
    service_ms = number(workload, :service_time_ms)
    peak_multiplier = number(workload, :peak_multiplier, 1.0)
    headroom = Keyword.get(opts, :headroom_fraction, 0.30)
    target_utilization = Keyword.get(opts, :target_utilization, 0.70)
    per_worker = Keyword.get(opts, :concurrency_per_worker, 1_000)
    per_partition = Keyword.get(opts, :concurrency_per_partition, 50_000)

    refusals =
      []
      |> invalid_if(not positive_number?(arrival_rate), :arrival_rate_per_second, arrival_rate)
      |> invalid_if(not positive_number?(service_ms), :service_time_ms, service_ms)
      |> invalid_if(not positive_number?(peak_multiplier), :peak_multiplier, peak_multiplier)
      |> invalid_if(not fraction?(headroom), :headroom_fraction, headroom)
      |> invalid_if(not fraction_open?(target_utilization), :target_utilization, target_utilization)
      |> invalid_if(not positive_number?(per_worker), :concurrency_per_worker, per_worker)
      |> invalid_if(not positive_number?(per_partition), :concurrency_per_partition, per_partition)

    if refusals == [] do
      base = arrival_rate * peak_multiplier * (service_ms / 1_000.0)
      with_headroom = base * (1.0 + headroom)
      required_concurrency = ceil(with_headroom / target_utilization)
      workers = ceil(required_concurrency / per_worker)
      partitions = ceil(required_concurrency / per_partition)

      capacity = %Capacity{
        required_concurrency: required_concurrency,
        required_workers: max(workers, 1),
        required_partitions: max(partitions, 1),
        headroom_fraction: headroom,
        target_utilization: target_utilization,
        assumptions: %{
          arrival_rate_per_second: arrival_rate,
          service_time_ms: service_ms,
          peak_multiplier: peak_multiplier,
          concurrency_per_worker: per_worker,
          concurrency_per_partition: per_partition,
          calculus: :littles_law
        },
        refusals: []
      }

      %{capacity | receipt_sha256: sha256(Map.from_struct(capacity))}
    else
      %Capacity{refusals: Enum.reverse(refusals), receipt_sha256: sha256(refusals)}
    end
  end

  @doc "Check observed SLIs against targets without manufacturing missing observations."
  def evaluate(observations, objectives \\ @default_objectives) when is_map(observations) do
    results =
      Enum.map(objectives, fn objective ->
        observed = Map.get(observations, objective.name, Map.get(observations, Atom.to_string(objective.name)))

        %{
          objective: objective.name,
          target: objective.target,
          observed: observed,
          status: objective_status(objective, observed),
          unit: objective.unit,
          criticality: objective.criticality
        }
      end)

    unknown = results |> Enum.filter(&(&1.status == :UNKNOWN)) |> Enum.map(& &1.objective)
    failed = results |> Enum.filter(&(&1.status == :FAILED)) |> Enum.map(& &1.objective)
    passed = results |> Enum.filter(&(&1.status == :VERIFIED)) |> Enum.map(& &1.objective)

    %{
      status: cond do
        failed != [] -> :BLOCKED
        unknown != [] -> :PARTIAL_ALIVE
        true -> :ALIVE
      end,
      standing: :slo_evaluation,
      passed: passed,
      failed: failed,
      unknown: unknown,
      results: results,
      receipt_sha256: sha256(results)
    }
  end

  defp objective_status(_objective, nil), do: :UNKNOWN

  defp objective_status(%Objective{name: name, target: target}, observed) when is_number(observed) do
    lower_is_better? = name in [:p50_latency, :p95_latency, :p99_latency, :queue_p99]
    passed? = if lower_is_better?, do: observed <= target, else: observed >= target
    if passed?, do: :VERIFIED, else: :FAILED
  end

  defp objective_status(_objective, _observed), do: :UNKNOWN

  defp number(map, key, default \\ nil), do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  defp positive_number?(value), do: is_number(value) and value > 0
  defp fraction?(value), do: is_number(value) and value >= 0 and value < 1
  defp fraction_open?(value), do: is_number(value) and value > 0 and value <= 1

  defp invalid_if(refusals, true, field, value) do
    [%{code: :REFUSED_INVALID_CAPACITY_INPUT, subject: field, evidence: %{value: inspect(value)}} | refusals]
  end

  defp invalid_if(refusals, false, _field, _value), do: refusals

  defp sha256(term) do
    term |> canonical() |> :erlang.term_to_binary([:deterministic]) |> :crypto.hash(:sha256) |> Base.encode16(case: :lower)
  end

  defp canonical(%_{} = struct), do: struct |> Map.from_struct() |> canonical()
  defp canonical(map) when is_map(map), do: map |> Enum.map(fn {k, v} -> {canonical(k), canonical(v)} end) |> Enum.sort()
  defp canonical(list) when is_list(list), do: Enum.map(list, &canonical/1)
  defp canonical(other), do: other
end

defmodule AshR2RML.Fortune5.Workload do
  @moduledoc "Workload intent and classification model with no execution authority."

  defmodule Intent do
    @moduledoc "Bounded request for workload placement."
    @enforce_keys [:work_class, :semantic_subject_sha256]
    defstruct [
      :work_class,
      :semantic_subject_sha256,
      :tenant_sha256,
      :region,
      :residency,
      :consistency,
      :authority,
      :deadline_ms,
      :estimated_cost,
      :idempotency_key_sha256,
      metadata: %{}
    ]

    @type t :: %__MODULE__{}
  end

  @classes %{
    interactive_read: %{priority: 80, mutable?: false, queue: :interactive, shed: :last},
    batch_read: %{priority: 30, mutable?: false, queue: :batch, shed: :first},
    compile: %{priority: 60, mutable?: false, queue: :compile, shed: :middle},
    manufacture: %{priority: 55, mutable?: false, queue: :manufacture, shed: :middle},
    verify: %{priority: 70, mutable?: false, queue: :verification, shed: :last},
    replay: %{priority: 75, mutable?: false, queue: :verification, shed: :last},
    receipted_write: %{priority: 90, mutable?: true, queue: :do, shed: :never_without_refusal},
    cutover: %{priority: 100, mutable?: true, queue: :authority, shed: :never_without_refusal}
  }

  def classes, do: @classes

  @doc "Build and validate one workload intent."
  def new(attrs) when is_map(attrs) do
    work_class = value(attrs, :work_class)
    semantic = value(attrs, :semantic_subject_sha256)
    tenant = value(attrs, :tenant_sha256)

    cond do
      not Map.has_key?(@classes, work_class) ->
        {:error, refusal(:REFUSED_UNKNOWN_WORK_CLASS, :work_class, %{value: inspect(work_class)})}

      not hash?(semantic) ->
        {:error, refusal(:REFUSED_INVALID_SEMANTIC_SUBJECT_IDENTITY, :semantic_subject_sha256, %{})}

      not is_nil(tenant) and not hash?(tenant) ->
        {:error, refusal(:REFUSED_INVALID_TENANT_IDENTITY, :tenant_sha256, %{})}

      @classes[work_class].mutable? and work_class != :cutover and not hash?(value(attrs, :idempotency_key_sha256)) ->
        {:error, refusal(:REFUSED_MUTATION_WITHOUT_IDEMPOTENCY, work_class, %{})}

      true ->
        {:ok,
         struct(Intent, %{
           work_class: work_class,
           semantic_subject_sha256: semantic,
           tenant_sha256: tenant,
           region: value(attrs, :region),
           residency: value(attrs, :residency),
           consistency: value(attrs, :consistency),
           authority: value(attrs, :authority),
           deadline_ms: value(attrs, :deadline_ms),
           estimated_cost: value(attrs, :estimated_cost),
           idempotency_key_sha256: value(attrs, :idempotency_key_sha256),
           metadata: value(attrs, :metadata) || %{}
         })}
    end
  end

  def class(%Intent{work_class: class}), do: Map.fetch!(@classes, class)

  defp value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp hash?(value), do: is_binary(value) and String.match?(value, ~r/\A[0-9a-fA-F]{64}\z/)
  defp refusal(code, subject, evidence), do: %{code: code, subject: subject, detail: "workload admission refused", evidence: evidence}
end

defmodule AshR2RML.Fortune5.Quota do
  @moduledoc "Hierarchical deterministic quota admission before runtime execution."

  defmodule Limit do
    @moduledoc "One quota bound."
    @enforce_keys [:scope, :metric, :limit]
    defstruct [:scope, :scope_sha256, :metric, :limit, :window_ms, burst: 0]
    @type t :: %__MODULE__{}
  end

  defmodule Usage do
    @moduledoc "Observed usage bound to a quota scope."
    @enforce_keys [:scope, :metric, :used]
    defstruct [:scope, :scope_sha256, :metric, :used, :window_started_at]
    @type t :: %__MODULE__{}
  end

  @default_limits [
    %Limit{scope: :global, metric: :concurrent_operations, limit: 1_000_000, burst: 100_000},
    %Limit{scope: :tenant, metric: :concurrent_operations, limit: 10_000, burst: 1_000},
    %Limit{scope: :tenant, metric: :queries_per_second, limit: 5_000, window_ms: 1_000, burst: 500},
    %Limit{scope: :tenant, metric: :generated_bytes_per_minute, limit: 1_073_741_824, window_ms: 60_000},
    %Limit{scope: :cell, metric: :concurrent_operations, limit: 100_000, burst: 10_000},
    %Limit{scope: :external_engine, metric: :concurrent_queries, limit: 5_000, burst: 500}
  ]

  def defaults, do: @default_limits

  @doc "Admit requested deltas against observed usage and configured limits. UNKNOWN is never admitted."
  def admit(requests, usages, limits \\ @default_limits) when is_list(requests) and is_list(usages) do
    usage_index = Map.new(usages, &{{&1.scope, &1.scope_sha256, &1.metric}, &1})

    results =
      Enum.map(requests, fn request ->
        scope = value(request, :scope)
        scope_sha = value(request, :scope_sha256)
        metric = value(request, :metric)
        delta = value(request, :delta) || 0
        limit = find_limit(limits, scope, scope_sha, metric)
        usage = Map.get(usage_index, {scope, scope_sha, metric}, %Usage{scope: scope, scope_sha256: scope_sha, metric: metric, used: 0})
        evaluate_limit(limit, usage, delta)
      end)

    refused = Enum.filter(results, &(&1.status == :REFUSED))
    unknown = Enum.filter(results, &(&1.status == :UNKNOWN))

    status =
      cond do
        refused != [] -> :REFUSED
        unknown != [] -> :UNKNOWN
        true -> :PARTIAL_ALIVE
      end

    standing =
      case status do
        :REFUSED -> :quota_refused
        :UNKNOWN -> :quota_unadmitted
        :PARTIAL_ALIVE -> :quota_admitted_not_executed
      end

    %{
      status: status,
      standing: standing,
      results: results,
      refusal_count: length(refused),
      unknown_count: length(unknown),
      receipt_sha256: sha256(results)
    }
  end

  defp find_limit(limits, scope, scope_sha, metric) do
    Enum.find(limits, fn limit ->
      limit.scope == scope and limit.metric == metric and
        (is_nil(limit.scope_sha256) or limit.scope_sha256 == scope_sha)
    end)
  end

  defp evaluate_limit(nil, usage, delta) do
    %{status: :UNKNOWN, scope: usage.scope, metric: usage.metric, delta: delta, detail: :no_admitted_limit}
  end

  defp evaluate_limit(%Limit{} = limit, %Usage{} = usage, delta) when is_number(delta) and delta >= 0 do
    projected = usage.used + delta
    ceiling = limit.limit + limit.burst

    if projected <= ceiling do
      %{status: :ADMITTED, scope: usage.scope, metric: usage.metric, used: usage.used, delta: delta, projected: projected, ceiling: ceiling}
    else
      %{status: :REFUSED, code: :REFUSED_QUOTA_EXCEEDED, scope: usage.scope, metric: usage.metric, used: usage.used, delta: delta, projected: projected, ceiling: ceiling}
    end
  end

  defp evaluate_limit(%Limit{} = limit, usage, delta) do
    %{status: :REFUSED, code: :REFUSED_INVALID_QUOTA_DELTA, scope: usage.scope, metric: limit.metric, delta: inspect(delta)}
  end

  defp value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp sha256(term), do: term |> :erlang.term_to_binary([:deterministic]) |> :crypto.hash(:sha256) |> Base.encode16(case: :lower)
end

defmodule AshR2RML.Fortune5.Router do
  @moduledoc """
  Deterministic candidate/cell routing planner.

  Routing is SELECT/CONSTRUCT. It emits a plan but never opens a connection,
  sends a query, or mutates a workload. The same semantic subject, tenant and
  candidate set produce the same placement unless an admitted topology changes.
  """

  alias AshR2RML.Fortune5.{DfCM, Quota, Workload}

  defmodule Cell do
    @moduledoc "One routable cell."
    @enforce_keys [:id, :region]
    defstruct [:id, :region, :residency, :capacity_class, :environment_sha256, labels: %{}, capabilities: []]
    @type t :: %__MODULE__{}
  end

  defmodule Plan do
    @moduledoc "Deterministic route plan; not execution authority."
    defstruct [
      :status,
      :standing,
      :candidate_id,
      :cell_id,
      :region,
      :route_key_sha256,
      :plan_sha256,
      :quota_receipt_sha256,
      :semantic_subject_sha256,
      :tenant_sha256,
      required_authority: :none,
      fallbacks: [],
      refusals: []
    ]

    @type t :: %__MODULE__{}
  end

  @read_classes [:interactive_read, :batch_read, :verify, :replay]
  @construct_classes [:compile, :manufacture]
  @do_classes [:receipted_write, :cutover]

  @doc "Route one admitted workload across an admitted candidate frontier and cell catalog."
  def route(%Workload.Intent{} = intent, candidates, cells, opts \\ []) do
    quota = Keyword.get(opts, :quota)

    with {:ok, candidate} <- choose_candidate(intent, candidates),
         :ok <- execution_compatible(intent, candidate),
         {:ok, eligible} <- eligible_cells(intent, candidate, cells),
         {:ok, quota_receipt} <- quota_admission(intent, quota),
         {:ok, selected, fallbacks} <- rendezvous(intent, candidate, eligible) do
      base = %Plan{
        status: :PARTIAL_ALIVE,
        standing: :route_constructed_not_executed,
        candidate_id: candidate.id,
        cell_id: selected.id,
        region: selected.region,
        route_key_sha256: route_key(intent, candidate),
        quota_receipt_sha256: quota_receipt,
        semantic_subject_sha256: intent.semantic_subject_sha256,
        tenant_sha256: intent.tenant_sha256,
        required_authority: required_authority(intent.work_class),
        fallbacks: Enum.map(fallbacks, & &1.id),
        refusals: []
      }

      {:ok, %{base | plan_sha256: sha256(Map.from_struct(base))}}
    else
      {:error, refusal} ->
        {:error,
         %Plan{
           status: :REFUSED,
           standing: :no_route,
           semantic_subject_sha256: intent.semantic_subject_sha256,
           tenant_sha256: intent.tenant_sha256,
           refusals: [refusal],
           plan_sha256: sha256(refusal)
         }}
    end
  end

  @doc "Construct a deterministic default cell catalog for simulation and planning."
  def cells(regions \\ ["us-west-2", "us-east-1"], cells_per_region \\ 3)
      when is_list(regions) and is_integer(cells_per_region) and cells_per_region > 0 do
    for region <- regions, ordinal <- 1..cells_per_region do
      id = "#{region}-cell-#{ordinal}"

      %Cell{
        id: id,
        region: region,
        residency: region,
        capacity_class: :standard,
        environment_sha256: sha256({region, ordinal, :environment}),
        labels: %{ordinal: ordinal},
        capabilities: [:sparql_read, :semantic_compile, :ggen_construct]
      }
    end
  end

  defp choose_candidate(intent, candidates) do
    compatible =
      candidates
      |> Enum.filter(&match?(%DfCM.Candidate{refusals: []}, &1))
      |> Enum.filter(&intent_candidate_compatible?(intent, &1))
      |> Enum.sort_by(fn candidate -> {-candidate.score, length(candidate.irreversible_edges), candidate.id} end)

    case compatible do
      [candidate | _] -> {:ok, candidate}
      [] -> {:error, refusal(:REFUSED_NO_DFCM_CANDIDATE, intent.work_class, %{candidate_count: length(candidates)})}
    end
  end

  defp intent_candidate_compatible?(intent, candidate) do
    a = candidate.assignment
    consistency_ok? = is_nil(intent.consistency) or intent.consistency == a.consistency_model
    residency_ok? = is_nil(intent.residency) or residency_candidate?(intent.residency, a.data_residency)
    consistency_ok? and residency_ok? and work_execution_compatible?(intent.work_class, a.execution_mode)
  end

  defp execution_compatible(intent, candidate) do
    if work_execution_compatible?(intent.work_class, candidate.assignment.execution_mode) do
      :ok
    else
      {:error, refusal(:REFUSED_EXECUTION_MODE, intent.work_class, %{execution_mode: candidate.assignment.execution_mode})}
    end
  end

  defp work_execution_compatible?(work_class, :receipted_write_runtime),
    do: work_class in @read_classes or work_class in @construct_classes or work_class in @do_classes

  defp work_execution_compatible?(work_class, :read_only_runtime),
    do: work_class in @read_classes or work_class in @construct_classes

  defp work_execution_compatible?(work_class, :compile_only), do: work_class in @construct_classes
  defp work_execution_compatible?(_work_class, _mode), do: false

  defp residency_candidate?(_requested, :unrestricted), do: true
  defp residency_candidate?(_requested, :country_pinned), do: true
  defp residency_candidate?(_requested, :region_pinned), do: true
  defp residency_candidate?(_requested, :sovereign_cell), do: true
  defp residency_candidate?(_requested, _), do: false

  defp eligible_cells(intent, candidate, cells) do
    eligible =
      cells
      |> Enum.filter(&region_compatible?(intent, candidate.assignment, &1))
      |> Enum.filter(&capability_compatible?(intent, &1))
      |> Enum.sort_by(& &1.id)

    case eligible do
      [] -> {:error, refusal(:REFUSED_NO_ELIGIBLE_CELL, intent.work_class, %{requested_region: intent.region, residency: intent.residency})}
      _ -> {:ok, eligible}
    end
  end

  defp region_compatible?(intent, assignment, cell) do
    explicit_region_ok? = is_nil(intent.region) or intent.region == cell.region

    residency_ok? =
      case assignment.data_residency do
        :unrestricted -> true
        :country_pinned -> true
        :region_pinned -> is_nil(intent.region) or intent.region == cell.region
        :sovereign_cell -> not is_nil(intent.residency) and intent.residency == cell.residency
        _ -> false
      end

    explicit_region_ok? and residency_ok?
  end

  defp capability_compatible?(%Workload.Intent{work_class: work_class}, cell)
       when work_class in [:interactive_read, :batch_read],
       do: :sparql_read in cell.capabilities

  defp capability_compatible?(%Workload.Intent{work_class: :compile}, cell),
    do: :semantic_compile in cell.capabilities

  defp capability_compatible?(%Workload.Intent{work_class: :manufacture}, cell),
    do: :ggen_construct in cell.capabilities

  defp capability_compatible?(%Workload.Intent{work_class: work_class}, _cell)
       when work_class in [:verify, :replay],
       do: true

  defp capability_compatible?(%Workload.Intent{work_class: work_class}, cell)
       when work_class in [:receipted_write, :cutover],
       do: :brce_do in cell.capabilities

  defp capability_compatible?(_intent, _cell), do: false

  defp quota_admission(_intent, nil), do: {:ok, nil}

  defp quota_admission(intent, %{requests: requests, usages: usages} = quota) do
    result = Quota.admit(requests, usages, Map.get(quota, :limits, Quota.defaults()))

    case result.status do
      :PARTIAL_ALIVE -> {:ok, result.receipt_sha256}
      :REFUSED -> {:error, refusal(:REFUSED_QUOTA, intent.work_class, %{quota_receipt_sha256: result.receipt_sha256})}
      :UNKNOWN -> {:error, refusal(:REFUSED_QUOTA_UNADMITTED, intent.work_class, %{quota_receipt_sha256: result.receipt_sha256})}
    end
  end

  defp quota_admission(intent, _other),
    do: {:error, refusal(:REFUSED_INVALID_QUOTA_CONTEXT, intent.work_class, %{})}

  defp rendezvous(intent, candidate, cells) do
    route_key = route_key(intent, candidate)

    ranked =
      cells
      |> Enum.map(fn cell -> {rendezvous_score(route_key, cell.id), cell} end)
      |> Enum.sort_by(fn {score, cell} -> {-score, cell.id} end)
      |> Enum.map(&elem(&1, 1))

    case ranked do
      [selected | rest] -> {:ok, selected, rest}
      [] -> {:error, refusal(:REFUSED_NO_ELIGIBLE_CELL, candidate.id, %{})}
    end
  end

  defp rendezvous_score(route_key, cell_id) do
    <<score::unsigned-big-integer-size(64), _rest::binary>> = :crypto.hash(:sha256, route_key <> "\0" <> cell_id)
    score
  end

  defp route_key(intent, candidate) do
    sha256({intent.semantic_subject_sha256, intent.tenant_sha256, intent.work_class, candidate.id})
  end

  defp required_authority(:receipted_write), do: :brce
  defp required_authority(:cutover), do: :cutover_authority
  defp required_authority(_), do: :none

  defp refusal(code, subject, evidence),
    do: %{code: code, subject: subject, detail: "routing admission refused", evidence: evidence}

  defp sha256(term), do: term |> :erlang.term_to_binary([:deterministic]) |> :crypto.hash(:sha256) |> Base.encode16(case: :lower)
end
