# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.MaterializationBound do
  @moduledoc false
  # Fail-closed default bounds for the pure materializers (Parity, Delta, NQuads): an item bound
  # (`:max`, default application env `:max_materialization_items`, 1_000_000) and a byte bound
  # (`:max_bytes`, default env `:max_materialization_bytes`, 64 MiB, measured with
  # `:erlang.external_size/1`, which does not allocate the encoding). `:infinity` opts out.

  alias AshR2RML.Refusal

  @default_items 1_000_000
  @default_bytes 67_108_864

  @spec check(atom(), String.t(), non_neg_integer(), term(), keyword()) ::
          :ok | {:error, Refusal.t()}
  def check(subject, label, count, term, opts) do
    items = limit(opts, :max, :max_materialization_items, @default_items)
    bytes = limit(opts, :max_bytes, :max_materialization_bytes, @default_bytes)

    cond do
      exceeds?(count, items) ->
        refuse(subject, "#{label} count #{count} exceeds max #{items}", %{count: count, max: items})

      bytes != :infinity and exceeds?(:erlang.external_size(term), bytes) ->
        size = :erlang.external_size(term)

        refuse(subject, "#{label} size #{size} bytes exceeds max_bytes #{bytes}", %{
          bytes: size,
          max_bytes: bytes
        })

      true ->
        :ok
    end
  end

  defp limit(opts, key, env_key, default) do
    case Keyword.fetch(opts, key) do
      {:ok, :infinity} -> :infinity
      {:ok, n} when is_integer(n) and n >= 0 -> n
      _ -> Application.get_env(:ash_r2rml, env_key, default)
    end
  end

  defp exceeds?(_n, :infinity), do: false
  defp exceeds?(n, max), do: n > max

  defp refuse(subject, detail, evidence) do
    {:error, Refusal.new(:REFUSED_RESOURCE_BOUND, subject, detail, evidence)}
  end
end
