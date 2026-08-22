# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.DfCM.StorageProbe do
  @moduledoc """
  Deterministic, CONSTRUCT-only experiment contracts for relationship storage candidates.

  A probe plan preserves every candidate returned by `AshR2RML.DfCM.storage_candidates/1`.
  It never chooses a storage strategy and never actuates a database. Observations can only
  promote a candidate to probe-scoped `ALIVE` when they bind an executed receipt to the
  exact plan and semantic subject.
  """

  alias AshR2RML.{DfCM, Refusal}
  alias AshR2RML.SemanticIR.Relationship

  defmodule Plan do
    @moduledoc false
    @enforce_keys [:id, :subject_sha256, :relationship, :candidate, :required_checks, :falsifiers]
    defstruct [:id, :subject_sha256, :relationship, :candidate, :required_checks, :falsifiers]

    @type t :: %__MODULE__{
            id: String.t(),
            subject_sha256: String.t(),
            relationship: atom(),
            candidate: AshR2RML.SemanticIR.Relationship.storage_strategy(),
            required_checks: [atom()],
            falsifiers: [atom()]
          }
  end

  defmodule Result do
    @moduledoc false
    @enforce_keys [:plan_id, :subject_sha256, :candidate, :standing]
    defstruct [:plan_id, :subject_sha256, :candidate, :standing, :receipt_sha256, blocked: []]

    @type t :: %__MODULE__{
            plan_id: String.t(),
            subject_sha256: String.t(),
            candidate: AshR2RML.SemanticIR.Relationship.storage_strategy(),
            standing: :ALIVE | :PARTIAL_ALIVE,
            receipt_sha256: String.t() | nil,
            blocked: [atom()]
          }
  end

  @candidate_order [
    :foreign_key,
    :join_table,
    :association_resource,
    :array,
    :jsonb,
    :computed_projection
  ]

  @requirements %{
    foreign_key: [:semantic_edge_preserved, :destination_identity_proven, :cardinality_concordant],
    join_table: [
      :semantic_edge_preserved,
      :join_identity_proven,
      :destination_identity_proven,
      :cardinality_concordant
    ],
    association_resource: [
      :semantic_edge_preserved,
      :association_identity_proven,
      :source_edge_proven,
      :target_edge_proven,
      :cardinality_concordant
    ],
    array: [:semantic_edge_preserved, :round_trip_lossless, :cardinality_concordant],
    jsonb: [:semantic_edge_preserved, :round_trip_lossless, :cardinality_concordant],
    computed_projection: [
      :semantic_edge_preserved,
      :source_query_deterministic,
      :destination_identity_proven,
      :cardinality_concordant
    ]
  }

  @falsifiers [
    :semantic_edge_loss,
    :identity_collision,
    :cardinality_mismatch,
    :nondeterministic_replay,
    :unreceipted_actuation
  ]

  @spec plans(Relationship.t(), String.t()) :: {:ok, [Plan.t()]} | {:error, Refusal.t()}
  def plans(%Relationship{} = relationship, subject_sha256)
      when is_binary(subject_sha256) and subject_sha256 != "" do
    plans =
      relationship
      |> DfCM.storage_candidates()
      |> Enum.sort_by(&candidate_rank/1)
      |> Enum.map(&build_plan(relationship, subject_sha256, &1))

    {:ok, plans}
  end

  def plans(%Relationship{} = relationship, subject_sha256) do
    {:error,
     Refusal.new(
       :REFUSED_STORAGE_PROBE_SUBJECT_MISMATCH,
       relationship.name,
       "storage probes require a non-empty exact semantic subject identity",
       %{subject_sha256: subject_sha256}
     )}
  end

  @spec observe(Plan.t(), map()) :: {:ok, Result.t()} | {:error, Refusal.t()}
  def observe(%Plan{} = plan, observation) when is_map(observation) do
    with :ok <- exact_binding(plan, observation),
         :ok <- falsifiers_clear(plan, observation),
         :ok <- required_checks_pass(plan, observation) do
      executed? = get(observation, :executed?, false)
      receipt_sha256 = get(observation, :receipt_sha256)

      if executed? and nonempty?(receipt_sha256) do
        {:ok,
         %Result{
           plan_id: plan.id,
           subject_sha256: plan.subject_sha256,
           candidate: plan.candidate,
           standing: :ALIVE,
           receipt_sha256: receipt_sha256,
           blocked: []
         }}
      else
        {:ok,
         %Result{
           plan_id: plan.id,
           subject_sha256: plan.subject_sha256,
           candidate: plan.candidate,
           standing: :PARTIAL_ALIVE,
           receipt_sha256: receipt_sha256,
           blocked: [:observed_execution_receipt]
         }}
      end
    end
  end

  def observe(%Plan{} = plan, observation) do
    {:error,
     Refusal.new(
       :REFUSED_STORAGE_PROBE_FAILED,
       plan.candidate,
       "storage probe observation must be a map",
       %{observation: inspect(observation)}
     )}
  end

  @doc "Returns every probe-scoped ALIVE candidate without selecting among them."
  @spec admitted_candidates([Result.t()]) :: [Relationship.storage_strategy()]
  def admitted_candidates(results) when is_list(results) do
    results
    |> Enum.filter(&match?(%Result{standing: :ALIVE}, &1))
    |> Enum.map(& &1.candidate)
    |> Enum.uniq()
    |> Enum.sort_by(&candidate_rank/1)
  end

  defp build_plan(relationship, subject_sha256, candidate) do
    required_checks = Map.fetch!(@requirements, candidate)

    payload = %{
      subject_sha256: subject_sha256,
      relationship: canonical_relationship(relationship),
      candidate: candidate,
      required_checks: required_checks,
      falsifiers: @falsifiers
    }

    %Plan{
      id: "storage-probe:sha256:" <> sha256(payload),
      subject_sha256: subject_sha256,
      relationship: relationship.name,
      candidate: candidate,
      required_checks: required_checks,
      falsifiers: @falsifiers
    }
  end

  defp exact_binding(plan, observation) do
    observed_plan = get(observation, :plan_id)
    observed_subject = get(observation, :subject_sha256)
    observed_candidate = normalize_candidate(get(observation, :candidate))

    cond do
      observed_plan != plan.id ->
        {:error,
         Refusal.new(
           :REFUSED_STORAGE_PROBE_SUBJECT_MISMATCH,
           plan.candidate,
           "observation is not bound to the exact probe plan",
           %{expected_plan_id: plan.id, observed_plan_id: observed_plan}
         )}

      observed_subject != plan.subject_sha256 ->
        {:error,
         Refusal.new(
           :REFUSED_STORAGE_PROBE_SUBJECT_MISMATCH,
           plan.candidate,
           "observation is not bound to the exact semantic subject",
           %{expected_subject: plan.subject_sha256, observed_subject: observed_subject}
         )}

      observed_candidate != plan.candidate ->
        {:error,
         Refusal.new(
           :REFUSED_STORAGE_PROBE_SUBJECT_MISMATCH,
           plan.candidate,
           "observation candidate differs from the planned candidate",
           %{expected_candidate: plan.candidate, observed_candidate: observed_candidate}
         )}

      true ->
        :ok
    end
  end

  defp required_checks_pass(plan, observation) do
    checks = get(observation, :checks, %{})
    failed = Enum.reject(plan.required_checks, &(get(checks, &1, false) == true))

    if failed == [] do
      :ok
    else
      {:error,
       Refusal.new(
         :REFUSED_STORAGE_PROBE_FAILED,
         plan.candidate,
         "required storage-candidate checks did not pass",
         %{failed_checks: failed}
       )}
    end
  end

  defp falsifiers_clear(plan, observation) do
    checks = get(observation, :checks, %{})
    triggered = Enum.filter(plan.falsifiers, &(get(checks, &1, false) == true))

    if triggered == [] do
      :ok
    else
      {:error,
       Refusal.new(
         :REFUSED_STORAGE_PROBE_FAILED,
         plan.candidate,
         "storage candidate triggered an explicit falsifier",
         %{triggered_falsifiers: triggered}
       )}
    end
  end

  defp canonical_relationship(%Relationship{} = relationship) do
    relationship
    |> Map.from_struct()
    |> canonical()
  end

  defp sha256(term) do
    term
    |> canonical()
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp canonical(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> {key, canonical(value)} end)
    |> Enum.sort_by(fn {key, _value} -> inspect(key) end)
  end

  defp canonical(list) when is_list(list), do: Enum.map(list, &canonical/1)
  defp canonical(other), do: other

  defp candidate_rank(candidate), do: Enum.find_index(@candidate_order, &(&1 == candidate)) || 999

  defp normalize_candidate(candidate) when is_atom(candidate), do: candidate

  defp normalize_candidate(candidate) when is_binary(candidate) do
    Enum.find(@candidate_order, &(Atom.to_string(&1) == candidate))
  end

  defp normalize_candidate(_), do: nil

  defp nonempty?(value), do: is_binary(value) and value != ""

  defp get(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end
end
