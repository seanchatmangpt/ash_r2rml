defmodule AshR2RML.VKG.Result do
  @moduledoc """
  Deterministic normalized result of a VKG plan.

  Rows retain their source contract identity in the reserved "_vkg" field.
  Normalization sorts map keys and row order before hashing so receipts remain
  stable across equivalent engine ordering.
  """

  @enforce_keys [:plan_sha256, :rows, :row_count, :sha256]
  defstruct [:plan_sha256, :rows, :row_count, :sha256, :sources, standing: :observed_not_actuated]

  @type t :: %__MODULE__{}

  @spec build(String.t(), [map()]) :: t()
  def build(plan_sha256, rows) when is_list(rows) do
    normalized = rows |> Enum.map(&normalize_row/1) |> Enum.sort_by(&row_sort_key/1)

    %__MODULE__{
      plan_sha256: plan_sha256,
      rows: normalized,
      row_count: length(normalized),
      sources: source_counts(normalized),
      sha256: hash({plan_sha256, normalized}),
      standing: :observed_not_actuated
    }
  end

  @spec equivalent?(t(), t()) :: boolean()
  def equivalent?(%__MODULE__{} = left, %__MODULE__{} = right) do
    left.plan_sha256 == right.plan_sha256 and left.sha256 == right.sha256
  end

  @spec subject_index(t()) :: %{optional(String.t()) => [map()]}
  def subject_index(%__MODULE__{rows: rows}) do
    Enum.group_by(rows, fn row -> get_in(row, ["_vkg", "subject"]) end)
  end

  @spec source_index(t()) :: %{optional(String.t()) => [map()]}
  def source_index(%__MODULE__{rows: rows}) do
    Enum.group_by(rows, fn row -> get_in(row, ["_vkg", "contract_id"]) end)
  end

  defp normalize_row(row) when is_map(row) do
    row
    |> Enum.map(fn {key, value} -> {to_string(key), normalize_value(value)} end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Map.new()
  end

  defp normalize_row(other), do: %{"value" => normalize_value(other)}

  defp normalize_value(map) when is_map(map), do: normalize_row(map)
  defp normalize_value(list) when is_list(list), do: Enum.map(list, &normalize_value/1)
  defp normalize_value(other), do: other

  defp row_sort_key(row), do: :erlang.term_to_binary(row, [:deterministic])

  defp source_counts(rows) do
    rows
    |> Enum.map(&get_in(&1, ["_vkg", "contract_id"]))
    |> Enum.reject(&is_nil/1)
    |> Enum.frequencies()
  end

  defp hash(term) do
    term
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
