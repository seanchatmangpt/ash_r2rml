# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Money do
  @moduledoc """
  Monetary composite projection: one monetary node per value.

  A monetary value projects to a node of class `monetary_amount_class/0`
  carrying an `xsd:decimal` amount (Decimal lexical form, never a float) and a
  currency IRI. AshMoney / ex_money are optional: values are recognised by
  struct shape (`%Money{amount: %Decimal{}, currency: atom}`) and types by
  module name, with no compile-time or runtime dependency. A hand-written
  composite implements `AshR2RML.Type` with `semantic_kind: :value_object`
  and returns `{:node, %{amount: ..., currency: ...}}` from `to_rdf/1`.

  Anything else is a typed `REFUSED_UNMAPPED_DATATYPE` refusal.

  ## Examples

      iex> {:ok, node} = AshR2RML.Money.project(Decimal.new("45.50"), currency: "USD")
      iex> node.amount
      {:literal, "45.50", "http://www.w3.org/2001/XMLSchema#decimal"}
      iex> node.currency_iri
      "https://spec.edmcouncil.org/fibo/ontology/FND/Accounting/CurrencyAmount/USD"

      iex> {:error, refusal} = AshR2RML.Money.project(45.5, currency: "USD")
      iex> refusal.code
      :REFUSED_UNMAPPED_DATATYPE
  """

  alias AshR2RML.Refusal

  @xsd_decimal "http://www.w3.org/2001/XMLSchema#decimal"
  @class "https://spec.edmcouncil.org/fibo/ontology/FND/Accounting/CurrencyAmount/MonetaryAmount"
  @currency_base "https://spec.edmcouncil.org/fibo/ontology/FND/Accounting/CurrencyAmount/"

  @money_modules ["Elixir.AshMoney.Types.Money", "Elixir.Money"]

  @type node_t :: %{
          class_iri: String.t(),
          amount: {:literal, String.t(), String.t()},
          currency_iri: String.t() | nil
        }

  @spec monetary_amount_class() :: String.t()
  def monetary_amount_class, do: @class

  @doc "True when the Ash type is an AshMoney-style money type (by module name)."
  @spec money_type?(term()) :: boolean()
  def money_type?(type) when is_atom(type) and not is_nil(type),
    do: Atom.to_string(type) in @money_modules

  def money_type?(_), do: false

  @doc """
  Projects a Decimal, a Money-shaped struct, or a hand-written composite node.

  Options: `:currency` (ISO 4217 code, for bare Decimals), `:currency_base_iri`
  (must be an absolute IRI; otherwise a typed refusal).
  A bare Decimal without `:currency` projects with `currency_iri: nil`.
  """
  @spec project(term(), keyword()) :: {:ok, node_t()} | {:error, Refusal.t()}
  def project(value, opts \\ [])

  def project(%Decimal{} = amount, opts) do
    case Keyword.get(opts, :currency) do
      nil -> build(amount, nil, opts)
      currency -> build(amount, currency, opts)
    end
  end

  def project(%{__struct__: struct, amount: %Decimal{} = amount, currency: currency}, opts)
      when is_atom(currency) or is_binary(currency) do
    if Atom.to_string(struct) in @money_modules do
      build(amount, currency, opts)
    else
      refuse(struct, "struct is not a recognised Money shape")
    end
  end

  def project({:node, %{amount: %Decimal{} = amount, currency: currency}}, opts),
    do: build(amount, currency, opts)

  def project({:node, %{amount: {:literal, lexical, @xsd_decimal}, currency: currency}}, opts) do
    case Decimal.parse(lexical) do
      {%Decimal{} = amount, ""} -> build(amount, currency, opts)
      _ -> refuse(lexical, "amount literal is not a Decimal lexical")
    end
  end

  def project(other, _opts),
    do: refuse(other, "value is not a Decimal or Money-shaped composite (floats are refused)")

  defp build(%Decimal{} = amount, currency, opts) do
    if Decimal.nan?(amount) or Decimal.inf?(amount) do
      refuse(amount, "non-finite decimal has no xsd:decimal lexical form")
    else
      with {:ok, base} <- base_iri(opts),
           {:ok, currency_iri} <- currency_iri(currency, base) do
        {:ok,
         %{
           class_iri: @class,
           amount: {:literal, Decimal.to_string(amount, :normal), @xsd_decimal},
           currency_iri: currency_iri
         }}
      end
    end
  end

  defp base_iri(opts) do
    case Keyword.get(opts, :currency_base_iri, @currency_base) do
      base when is_binary(base) ->
        case URI.parse(base) do
          %URI{scheme: scheme} when is_binary(scheme) and scheme != "" -> {:ok, base}
          _ -> refuse(base, ":currency_base_iri must be an absolute IRI")
        end

      other ->
        refuse(other, ":currency_base_iri must be an absolute IRI string")
    end
  end

  defp currency_iri(nil, _base), do: {:ok, nil}

  defp currency_iri(currency, base) when is_atom(currency) or is_binary(currency) do
    code = currency |> to_string() |> String.upcase()

    if Regex.match?(~r/\A[A-Z]{3}\z/, code) do
      {:ok, base <> code}
    else
      refuse(currency, "currency is not an ISO 4217 alphabetic code")
    end
  end

  defp currency_iri(currency, _base), do: refuse(currency, "currency is not a code")

  defp refuse(subject, detail),
    do: {:error, Refusal.new(:REFUSED_UNMAPPED_DATATYPE, subject, detail)}
end
