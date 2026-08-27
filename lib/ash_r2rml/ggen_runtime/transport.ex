# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.Transport do
  @moduledoc "API/CLI transport contract with bounded pagination, batching, and streaming."

  @spec admit(map()) :: {:ok, map()} | {:error, atom()}
  def admit(%{kind: kind, max_page_size: page} = contract)
      when kind in [:api, :cli] and is_integer(page) and page >= 1 and page <= 10_000 do
    batch = Map.get(contract, :max_batch_size, page)

    if is_integer(batch) and batch >= 1 and batch <= 10_000 do
      {:ok, Map.put_new(contract, :streaming, false)}
    else
      {:error, :REFUSED_RUNTIME_BATCH_UNBOUNDED}
    end
  end

  def admit(_), do: {:error, :REFUSED_RUNTIME_TRANSPORT_INCOMPLETE}
end
