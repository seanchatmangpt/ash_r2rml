defmodule AshR2RML.VKG.Result do
  @moduledoc """
  Deterministic normalized result of a VKG plan.

  Rows retain their source contract identity in the reserved "_vkg" field.
  Normalization sorts map keys and row order before hashing so receipts remain
  stable across equivalent engine ordering. Values are projected to JSON-native
  form so sealed results survive a JSON round trip; the projection is not what
  protects the digest (the canonical encoding is injective, see
  `AshR2RML.VKG.Serializer`), and per-stage observation digests are computed over
  the unprojected rows, so the type distinctions the projection erases stay bound
  in the receipt.
  """

  @enforce_keys [:plan_sha256, :rows, :row_count, :sha256]
  defstruct [:plan_sha256, :rows, :row_count, :sha256, :sources, standing: :observed_not_actuated]

  @type t :: %__MODULE__{}

  alias AshR2RML.Refusal
  alias AshR2RML.VKG.Serializer

  @standings [:observed_not_actuated, :test_double_only]

  @doc """
  Single source of truth for every standing a VKG result (and therefore a receipt,
  which derives its standing from the result) can carry. The serializer, the
  receipt integrity check and the executor all read this list.
  """
  @spec standings() :: [atom()]
  def standings, do: @standings

  @doc """
  Seals normalized rows. Values are normalized to JSON-native form (atoms,
  dates and decimals become strings, tuples become lists) so the canonical
  digest is injective over what a result can hold; `verify/1` refuses rows
  that are not already in that normal form.

  `standing` is part of the digest.
  """
  @spec build(String.t(), [map()], atom()) :: t()
  def build(plan_sha256, rows, standing \\ :observed_not_actuated)
      when is_list(rows) and standing in @standings do
    normalized = rows |> Enum.map(&normalize_row/1) |> Enum.sort_by(&row_sort_key/1)

    %__MODULE__{
      plan_sha256: plan_sha256,
      rows: normalized,
      row_count: length(normalized),
      sources: source_counts(normalized),
      sha256: compute_sha256(plan_sha256, normalized, standing),
      standing: standing
    }
  end

  @doc "Full sha256 over the canonical JSON of the plan digest, standing and normalized rows."
  @spec compute_sha256(String.t(), [map()], atom()) :: String.t()
  def compute_sha256(plan_sha256, rows, standing \\ :observed_not_actuated) do
    Serializer.digest(%{
      "kind" => "vkg.result",
      "plan_sha256" => plan_sha256,
      "rows" => rows,
      "standing" => standing
    })
  end

  @doc """
  Recomputes row count, source counts and digest from the stored rows.

  A result whose rows were mutated after sealing no longer verifies.
  """
  @spec verify(t()) :: :ok | {:error, Refusal.t()}
  def verify(%__MODULE__{rows: rows} = result) when is_list(rows) do
    cond do
      result.standing not in @standings ->
        refusal(:standing, "VKG result standing is not a known standing", %{standing: inspect(result.standing)})

      not is_integer(result.row_count) or result.row_count !== length(rows) ->
        refusal(:row_count, "VKG result row count does not match its rows", %{
          claimed: result.row_count,
          actual: length(rows)
        })

      result.sources != source_counts(rows) ->
        refusal(:sources, "VKG result source counts do not match its rows", %{})

      not normal_form?(rows) ->
        refusal(:rows, "VKG result rows are not in canonical JSON-native form", %{})

      result.sha256 != compute_sha256(result.plan_sha256, rows, result.standing) ->
        refusal(:result, "VKG result digest does not match its rows and standing", %{
          claimed: result.sha256,
          recomputed: compute_sha256(result.plan_sha256, rows, result.standing)
        })

      true ->
        :ok
    end
  end

  def verify(%__MODULE__{}), do: refusal(:rows, "VKG result rows must be a list", %{})

  defp refusal(subject, detail, evidence),
    do: {:error, Refusal.new(:REFUSED_VKG_REPLAY, subject, detail, evidence)}

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

  defp normalize_row(row) when is_map(row) and not is_struct(row) do
    row
    |> Enum.map(fn {key, value} -> {Serializer.key_string(key), is_binary(key), normalize_value(value)} end)
    # string keys sort after atom keys of the same name, so a string key wins a collision
    |> Enum.sort_by(fn {key, binary_key?, _value} -> {key, binary_key?} end)
    |> Map.new(fn {key, _binary_key?, value} -> {key, value} end)
  end

  defp normalize_row(other), do: %{"value" => normalize_value(other)}

  defp normalize_value(%module{} = struct) when module in [Date, Time, NaiveDateTime, DateTime, Decimal],
    do: to_string(struct)

  defp normalize_value(struct) when is_struct(struct), do: struct
  defp normalize_value(map) when is_map(map), do: normalize_row(map)
  defp normalize_value(list) when is_list(list), do: Enum.map(list, &normalize_value/1)
  defp normalize_value(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> normalize_value()
  defp normalize_value(nil), do: nil
  defp normalize_value(bool) when is_boolean(bool), do: bool
  defp normalize_value(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp normalize_value(other), do: other

  # Rows are in normal form when normalization is a no-op (keys already strings,
  # values JSON-native), so a value cannot change type while keeping its digest.
  defp normal_form?(rows) do
    Enum.all?(rows, fn row -> is_map(row) and not is_struct(row) and normalize_row(row) == row end)
  end

  defp row_sort_key(row), do: Serializer.canonical_json(row)

  defp source_counts(rows) do
    rows
    |> Enum.map(&get_in(&1, ["_vkg", "contract_id"]))
    |> Enum.reject(&is_nil/1)
    |> Enum.frequencies()
  end
end
