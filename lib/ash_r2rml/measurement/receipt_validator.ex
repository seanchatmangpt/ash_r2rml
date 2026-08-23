# SPDX-FileCopyrightText: 2026 ash_r2rml contributors
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Measurement.ReceiptValidator do
  @moduledoc """
  Fail-closed validation for human-readable execution receipts.

  The validator separates executed test failures from tests excluded by selection
  policy and can reject stale evidence when the caller supplies an explicit
  observation time. It never manufactures an age or exclusion denominator.
  """

  @type refusal ::
          :receipt_missing_exit_status
          | :receipt_missing_test_summary
          | :receipt_missing_timestamp
          | :receipt_invalid_timestamp
          | :receipt_contradictory_exclusions
          | :receipt_stale

  @spec validate(String.t(), keyword()) :: {:ok, map()} | {:error, refusal(), map()}
  def validate(receipt, opts \\ []) when is_binary(receipt) do
    with {:ok, exit_status} <- parse_exit_status(receipt),
         {:ok, tests, failures} <- parse_test_summary(receipt),
         {:ok, excluded_tags} <- parse_excluded_tags(receipt),
         :ok <- reconcile_exclusion_claim(receipt, excluded_tags),
         {:ok, observed_at} <- parse_timestamp(receipt),
         :ok <- validate_freshness(observed_at, opts) do
      {:ok,
       %{
         exit_status: exit_status,
         tests: tests,
         failures: failures,
         excluded_tags: excluded_tags,
         selection_exclusions?: excluded_tags != [],
         observed_at: observed_at
       }}
    end
  end

  defp parse_exit_status(receipt) do
    case Regex.run(~r/\*\*Exit Status\*\*:\s*`?(\d+)`?/, receipt) do
      [_, value] -> {:ok, String.to_integer(value)}
      _ -> {:error, :receipt_missing_exit_status, %{field: :exit_status}}
    end
  end

  defp parse_test_summary(receipt) do
    case Regex.run(~r/(\d+) tests,\s*(\d+) failures/, receipt) do
      [_, tests, failures] -> {:ok, String.to_integer(tests), String.to_integer(failures)}
      _ -> {:error, :receipt_missing_test_summary, %{field: :test_summary}}
    end
  end

  defp parse_excluded_tags(receipt) do
    case Regex.run(~r/Excluding tags:\s*\[([^\]]*)\]/, receipt) do
      [_, tags] ->
        parsed =
          Regex.scan(~r/:([a-zA-Z0-9_]+)/, tags, capture: :all_but_first)
          |> List.flatten()
          |> Enum.map(&String.to_atom/1)

        {:ok, parsed}

      _ ->
        {:ok, []}
    end
  end

  defp reconcile_exclusion_claim(receipt, excluded_tags) do
    claims_zero = Regex.match?(~r/Total Skipped\/Excluded\*\*:\s*0\b/, receipt)

    if claims_zero and excluded_tags != [] do
      {:error, :receipt_contradictory_exclusions,
       %{claimed_excluded: 0, observed_excluded_tags: excluded_tags}}
    else
      :ok
    end
  end

  defp parse_timestamp(receipt) do
    case Regex.run(~r/\*\*Execution Timestamp\*\*:\s*`([^`]+)`/, receipt) do
      [_, value] ->
        case DateTime.from_iso8601(value) do
          {:ok, datetime, _offset} -> {:ok, datetime}
          {:error, _} -> {:error, :receipt_invalid_timestamp, %{value: value}}
        end

      _ ->
        {:error, :receipt_missing_timestamp, %{field: :execution_timestamp}}
    end
  end

  defp validate_freshness(_observed_at, opts) when not is_list(opts), do: :ok

  defp validate_freshness(observed_at, opts) do
    case {Keyword.get(opts, :now), Keyword.get(opts, :max_age_seconds)} do
      {%DateTime{} = now, max_age} when is_integer(max_age) and max_age >= 0 ->
        age = DateTime.diff(now, observed_at, :second)

        if age > max_age do
          {:error, :receipt_stale, %{age_seconds: age, max_age_seconds: max_age}}
        else
          :ok
        end

      _ ->
        :ok
    end
  end
end
