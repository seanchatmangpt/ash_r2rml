defmodule AshR2RML.VKG.Serializer do
  @moduledoc """
  Stable JSON projections for VKG sessions and receipts.
  """

  alias AshR2RML.VKG.{Receipt, Result, Session}

  @spec receipt(Receipt.t()) :: map()
  def receipt(%Receipt{} = receipt) do
    %{
      "id" => receipt.id,
      "plan_sha256" => receipt.plan_sha256,
      "catalog_sha256" => receipt.catalog_sha256,
      "contract_ids" => receipt.contract_ids,
      "observation_sha256_by_contract" => receipt.observation_sha256_by_contract,
      "result_sha256" => receipt.result_sha256,
      "row_count" => receipt.row_count,
      "previous" => receipt.previous,
      "authority" => Atom.to_string(receipt.authority),
      "standing" => Atom.to_string(receipt.standing)
    }
  end

  @spec result(Result.t()) :: map()
  def result(%Result{} = result) do
    %{
      "plan_sha256" => result.plan_sha256,
      "rows" => result.rows,
      "row_count" => result.row_count,
      "sources" => result.sources,
      "sha256" => result.sha256,
      "standing" => Atom.to_string(result.standing)
    }
  end

  @spec session(Session.t()) :: map()
  def session(%Session{} = session) do
    %{
      "summary" => stringify(Session.summary(session)),
      "receipt" => receipt(session.receipt),
      "result" => result(session.result)
    }
  end

  @spec encode_receipt!(Receipt.t()) :: String.t()
  def encode_receipt!(%Receipt{} = receipt) do
    receipt
    |> receipt()
    |> canonical()
    |> Jason.encode!()
  end

  @spec encode_session!(Session.t()) :: String.t()
  def encode_session!(%Session{} = session) do
    session
    |> session()
    |> canonical()
    |> Jason.encode!()
  end

  defp canonical(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Enum.map(fn {key, value} -> {to_string(key), canonical(value)} end)
    |> Map.new()
  end

  defp canonical(list) when is_list(list), do: Enum.map(list, &canonical/1)
  defp canonical(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp canonical(value), do: value

  defp stringify(map) do
    Map.new(map, fn {key, value} -> {to_string(key), canonical(value)} end)
  end
end
