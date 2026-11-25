# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OBDA.InMemory.IriTemplate do
  @moduledoc """
  Pure `rr:template` substitution and IRI validation helpers used by
  `AshR2RML.OBDA.InMemory`.

  Every substituted value is percent-encoded (RFC 3986 unreserved characters stay literal) so a
  row value such as `a>b` cannot terminate an IRIREF early in serialized Turtle. The static,
  author-written portion of a template is never encoded.

  `:column` maps are different in kind: the stored value IS the whole IRI, so it is validated
  (`valid_iri_or_nil/1`) and skipped when malformed, never rewritten.

  ## Examples

      iex> alias AshR2RML.OBDA.InMemory.IriTemplate
      iex> IriTemplate.substitute("http://schema.org/{name}", %{name: "a>b"})
      "http://schema.org/a%3Eb"
      iex> IriTemplate.valid_iri_or_nil("http://schema.org/ok")
      "http://schema.org/ok"
  """

  @placeholder ~r/\{([a-zA-Z0-9_]+)\}/

  @doc """
  Substitutes `{field}` placeholders from `row`, percent-encoding each value.

  Raises `ArgumentError` for a field with no existing atom and `Protocol.UndefinedError` for a
  value without `String.Chars`; callers translate both into a nil (row-skipping) result.
  """
  @spec substitute(String.t(), map()) :: String.t()
  def substitute(template, row) do
    Regex.replace(@placeholder, template, fn _whole, field ->
      value = Map.get(row, String.to_existing_atom(field))

      case lexical(value) do
        {:ok, lex} -> encode(lex)
        :error -> raise ArgumentError, "no lexical form for template field #{field}"
      end
    end)
  end

  @doc """
  The single lexical serializer shared by subject templates, join keys and literals.

  ## Examples

      iex> AshR2RML.OBDA.InMemory.IriTemplate.lexical(~U[2026-01-02 03:04:05Z])
      {:ok, "2026-01-02T03:04:05Z"}
      iex> AshR2RML.OBDA.InMemory.IriTemplate.lexical(Decimal.new("1E+3"))
      {:ok, "1000"}
  """
  @spec lexical(term()) :: {:ok, String.t()} | :error
  def lexical(value) when is_binary(value), do: {:ok, value}
  def lexical(%Decimal{coef: coef}) when coef in [:NaN, :inf], do: :error
  def lexical(%Decimal{} = value), do: {:ok, Decimal.to_string(value, :normal)}
  def lexical(%Date{} = value), do: {:ok, Date.to_iso8601(value)}
  def lexical(%DateTime{} = value), do: {:ok, DateTime.to_iso8601(value)}
  def lexical(%NaiveDateTime{} = value), do: {:ok, NaiveDateTime.to_iso8601(value)}
  def lexical(%Time{} = value), do: {:ok, Time.to_iso8601(value)}
  def lexical(value) when is_number(value) or is_atom(value), do: {:ok, to_string(value)}

  def lexical(value) when is_struct(value) do
    if String.Chars.impl_for(value), do: {:ok, to_string(value)}, else: :error
  rescue
    _error in [ArgumentError, Protocol.UndefinedError] -> :error
  end

  def lexical(_value), do: :error

  @doc "Percent-encodes everything except RFC 3986 unreserved characters."
  @spec encode(String.t()) :: String.t()
  def encode(value), do: URI.encode(value, &URI.char_unreserved?/1)

  @doc "Returns `candidate` when it is a well-formed IRI, otherwise `nil`."
  @spec valid_iri_or_nil(term()) :: String.t() | nil
  def valid_iri_or_nil(candidate) do
    if valid_iri?(candidate), do: candidate, else: nil
  end

  @doc "True when `value` is a binary that parses as a valid IRI."
  @spec valid_iri?(term()) :: boolean()
  def valid_iri?(value) when is_binary(value) do
    value |> RDF.iri() |> RDF.IRI.valid?()
  rescue
    _error in [ArgumentError, RDF.IRI.InvalidError] -> false
  end

  def valid_iri?(_value), do: false

  @doc """
  True when every placeholder field of `template` is readable in `row` (not forbidden,
  not-loaded or nil). A denied field fails closed rather than leaking into an IRI.
  """
  @spec fields_readable?(String.t(), map()) :: boolean()
  def fields_readable?(template, row) do
    @placeholder
    |> Regex.scan(template, capture: :all_but_first)
    |> Enum.all?(fn [field] -> readable(Map.get(row, String.to_existing_atom(field))) != nil end)
  rescue
    ArgumentError -> false
  end

  @doc "Maps Ash's denied/unloaded sentinels to `nil`; any other value passes through."
  @spec readable(term()) :: term()
  def readable(%Ash.ForbiddenField{}), do: nil
  def readable(%Ash.NotLoaded{}), do: nil
  def readable(value), do: value
end
