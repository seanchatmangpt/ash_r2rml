defmodule AshR2RML.VKG.Replay do
  @moduledoc "Deterministic replay identity for admitted VKG reads."
  def identity(contract, query_sha256, rows_sha256) do
    :crypto.hash(:sha256, Enum.join([contract.source_sha256, contract.mapping_sha256, query_sha256, rows_sha256], ":")) |> Base.encode16(case: :lower)
  end
  def same?(expected, observed), do: expected == observed
end
