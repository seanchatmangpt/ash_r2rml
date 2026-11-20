# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.KnowledgeHook.ActuationReceipt do
  @moduledoc """
  Receipt for an independent actuation of a constructed Knowledge Hook intent.

  This is the opposite artifact of `AshR2RML.KnowledgeHook.EvaluationReceipt`:
  evaluation observes and may construct; actuation admits authority and DO.
  An evaluation receipt never upgrades into an actuation receipt by renaming.
  """

  @enforce_keys [
    :receipt_sha256,
    :hook_id,
    :evaluation_receipt_sha256,
    :target,
    :authority_sha256,
    :pre_state_sha256,
    :post_state_sha256,
    :effect_sha256
  ]
  defstruct [
    :receipt_sha256,
    :hook_id,
    :evaluation_receipt_sha256,
    :target,
    :kind,
    :authority_sha256,
    :brce_receipt_sha256,
    :pre_state_sha256,
    :post_state_sha256,
    :effect_sha256,
    :observed_effect,
    standing: :actuated_with_receipt,
    authority: :AUTHORIZED,
    consequence: :external_effect_observed,
    executed: [:authority_admission, :actuation, :effect_observation]
  ]

  @type t :: %__MODULE__{
          receipt_sha256: String.t(),
          hook_id: String.t(),
          evaluation_receipt_sha256: String.t(),
          target: term(),
          kind: atom() | nil,
          authority_sha256: String.t(),
          brce_receipt_sha256: String.t() | nil,
          pre_state_sha256: String.t(),
          post_state_sha256: String.t(),
          effect_sha256: String.t(),
          observed_effect: term(),
          standing: :actuated_with_receipt,
          authority: :AUTHORIZED,
          consequence: :external_effect_observed,
          executed: [atom()]
        }
end

defmodule AshR2RML.KnowledgeHook.Actuator do
  @moduledoc """
  Explicit BRCE-style actuation boundary for constructed Knowledge Hook intents.

  Knowledge Hooks remain construct-only. This module is the opposite side of the
  fence: given an already-constructed `%AshR2RML.KnowledgeHook.Intent{}` plus an
  explicit authority admission, it may perform a caller-supplied effect and emit
  an `ActuationReceipt`.

  The effect function is admitted only at this boundary — never inside a hook
  definition, intent payload, or evaluation path.
  """

  alias AshR2RML.KnowledgeHook.{ActuationReceipt, Intent}
  alias AshR2RML.{Compiler, Refusal}

  @doc """
  Actuate a constructed intent under explicit BRCE authority.

  Required `authority` keys:
  - `:brce?` must be `true`
  - `:authority_sha256`
  - `:brce_receipt_sha256`
  - `:pre_state_sha256` — caller-observed state identity before DO
  - `:post_state_sha256` — caller-observed state identity after DO

  Required `opts`:
  - `:perform` — 2-arity `(target, payload) -> {:ok, observed_effect} | {:error, term()}`
  """
  @spec actuate(Intent.t() | term(), map(), keyword()) ::
          {:ok, ActuationReceipt.t()} | {:error, Refusal.t()}
  def actuate(intent, authority, opts \\ [])

  def actuate(%Intent{} = intent, authority, opts) when is_map(authority) and is_list(opts) do
    perform = Keyword.get(opts, :perform)

    with :ok <- require_constructed_intent(intent),
         :ok <- require_brce_authority(authority, intent.hook_id),
         :ok <- require_perform(perform, intent.hook_id),
         {:ok, observed_effect} <- run_effect(perform, intent) do
      effect_sha256 = Compiler.sha256(%{observed_effect: canonicalize(observed_effect)})

      core = %{
        version: 1,
        hook_id: intent.hook_id,
        evaluation_receipt_sha256: intent.evaluation_receipt_sha256,
        kind: intent.kind,
        target: intent.target,
        authority_sha256: fetch(authority, :authority_sha256),
        brce_receipt_sha256: fetch(authority, :brce_receipt_sha256),
        pre_state_sha256: fetch(authority, :pre_state_sha256),
        post_state_sha256: fetch(authority, :post_state_sha256),
        effect_sha256: effect_sha256,
        standing: :actuated_with_receipt,
        authority: :AUTHORIZED,
        consequence: :external_effect_observed
      }

      {:ok,
       %ActuationReceipt{
         receipt_sha256: Compiler.sha256(core),
         hook_id: intent.hook_id,
         evaluation_receipt_sha256: intent.evaluation_receipt_sha256,
         target: intent.target,
         kind: intent.kind,
         authority_sha256: fetch(authority, :authority_sha256),
         brce_receipt_sha256: fetch(authority, :brce_receipt_sha256),
         pre_state_sha256: fetch(authority, :pre_state_sha256),
         post_state_sha256: fetch(authority, :post_state_sha256),
         effect_sha256: effect_sha256,
         observed_effect: observed_effect
       }}
    end
  end

  def actuate(other, _authority, _opts) do
    {:error,
     Refusal.new(
       :REFUSED_UNPROVEN_EQUIVALENCE,
       :knowledge_hook_actuator,
       "actuation requires a constructed Knowledge Hook intent",
       %{got: inspect(other)}
     )}
  end

  defp require_constructed_intent(%Intent{} = intent) do
    cond do
      intent.authority != :UNAUTHORIZED ->
        {:error,
         Refusal.new(
           :REFUSED_UNPROVEN_EQUIVALENCE,
           intent.hook_id,
           "actuation refuses intents that already claim authority",
           %{authority: intent.authority}
         )}

      intent.standing != :constructed_not_actuated ->
        {:error,
         Refusal.new(
           :REFUSED_UNPROVEN_EQUIVALENCE,
           intent.hook_id,
           "actuation requires standing constructed_not_actuated",
           %{standing: intent.standing}
         )}

      intent.requires_actuation_receipt? != true ->
        {:error,
         Refusal.new(
           :REFUSED_UNPROVEN_EQUIVALENCE,
           intent.hook_id,
           "actuation requires an intent that still demands an actuation receipt"
         )}

      not is_binary(intent.evaluation_receipt_sha256) or
          byte_size(intent.evaluation_receipt_sha256) != 64 ->
        {:error,
         Refusal.new(
           :REFUSED_UNPROVEN_EQUIVALENCE,
           intent.hook_id,
           "actuation must bind a 64-hex evaluation receipt identity",
           %{evaluation_receipt_sha256: intent.evaluation_receipt_sha256}
         )}

      is_nil(intent.target) ->
        {:error,
         Refusal.new(
           :REFUSED_UNPROVEN_EQUIVALENCE,
           intent.hook_id,
           "actuation requires a stable intent target"
         )}

      true ->
        :ok
    end
  end

  defp require_brce_authority(authority, hook_id) do
    required = [
      :authority_sha256,
      :brce_receipt_sha256,
      :pre_state_sha256,
      :post_state_sha256
    ]

    missing =
      required
      |> Enum.reject(&present_sha256?(fetch(authority, &1)))

    cond do
      fetch(authority, :brce?) != true ->
        {:error,
         Refusal.new(
           :REFUSED_UNPROVEN_EQUIVALENCE,
           hook_id,
           "BRCE is the exclusive Knowledge Hook actuation authority boundary",
           %{brce?: fetch(authority, :brce?)}
         )}

      missing != [] ->
        {:error,
         Refusal.new(
           :REFUSED_UNPROVEN_EQUIVALENCE,
           hook_id,
           "actuation authority is missing required consequence/replay identities",
           %{missing: missing}
         )}

      true ->
        :ok
    end
  end

  defp require_perform(perform, _hook_id) when is_function(perform, 2), do: :ok

  defp require_perform(perform, hook_id) do
    {:error,
     Refusal.new(
       :REFUSED_UNPROVEN_EQUIVALENCE,
       hook_id,
       "actuation requires opts[:perform] as a 2-arity effect admitted at the DO boundary",
       %{got: inspect(perform)}
     )}
  end

  defp run_effect(perform, %Intent{} = intent) do
    case perform.(intent.target, intent.payload || %{}) do
      {:ok, observed_effect} ->
        {:ok, observed_effect}

      {:error, reason} ->
        {:error,
         Refusal.new(
           :REFUSED_UNPROVEN_EQUIVALENCE,
           intent.hook_id,
           "actuation effect failed",
           %{reason: canonicalize(reason)}
         )}

      other ->
        {:error,
         Refusal.new(
           :REFUSED_UNPROVEN_EQUIVALENCE,
           intent.hook_id,
           "actuation effect must return {:ok, observed_effect} or {:error, reason}",
           %{got: inspect(other)}
         )}
    end
  rescue
    error ->
      {:error,
       Refusal.new(
         :REFUSED_UNPROVEN_EQUIVALENCE,
         intent.hook_id,
         "actuation effect raised",
         %{error: Exception.message(error)}
       )}
  end

  defp present_sha256?(value) when is_binary(value), do: byte_size(value) == 64
  defp present_sha256?(_), do: false

  defp fetch(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end

  defp canonicalize(value) when is_binary(value) or is_atom(value) or is_number(value) or is_boolean(value),
    do: value

  defp canonicalize(list) when is_list(list), do: Enum.map(list, &canonicalize/1)

  defp canonicalize(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> {canonicalize(k), canonicalize(v)} end)
    |> Enum.sort_by(fn {k, _} -> inspect(k) end)
  end

  defp canonicalize(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.map(&canonicalize/1)

  defp canonicalize(other), do: inspect(other)
end
