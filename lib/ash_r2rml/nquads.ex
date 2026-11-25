# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.NQuads do
  @moduledoc """
  Pure canonical N-Quads serializer.

  Input is a list of `{subject, predicate, object, graph}` quads whose terms are:

    * `{:iri, iri}`
    * `{:literal, lexical}` (plain, `xsd:string`)
    * `{:literal, lexical, {:datatype, iri}}`
    * `{:literal, lexical, {:lang, tag}}`
    * `nil` as graph, meaning the default graph (no graph label emitted)

  Output is deterministic: one line per distinct quad, lines sorted bytewise, duplicates
  removed, every line terminated by `"\\n"`. The result is therefore invariant under input
  order. Only the four canonical literal escapes (`\\\\`, `\\"`, `\\n`, `\\r`) are used;
  IRI characters that RDF 1.1 forbids are written as `\\uXXXX`. Language tags are
  lowercased and `xsd:string` datatypes are elided (RDF 1.1 equivalence).

  Blank nodes are not supported: any `{:bnode, _}` term (or any unrecognized term) yields
  `{:error, %AshR2RML.Refusal{code: :REFUSED_INVALID_TERM_MAP}}` with `evidence.reason`
  set to `:blank_node` or `:invalid_term`.

  ## Examples

      iex> quads = [
      ...>   {{:iri, "urn:uuid:b"}, {:iri, "http://xmlns.com/foaf/0.1/name"}, {:literal, "x"}, nil},
      ...>   {{:iri, "urn:uuid:a"}, {:iri, "http://xmlns.com/foaf/0.1/name"},
      ...>    {:literal, "hi\\n", {:lang, "EN"}}, {:iri, "urn:uuid:g"}}
      ...> ]
      iex> {:ok, out} = AshR2RML.NQuads.serialize(quads)
      iex> out
      "<urn:uuid:a> <http://xmlns.com/foaf/0.1/name> \\"hi\\\\n\\"@en <urn:uuid:g> .\\n<urn:uuid:b> <http://xmlns.com/foaf/0.1/name> \\"x\\" .\\n"

      iex> {:error, r} = AshR2RML.NQuads.serialize([{{:bnode, "b0"}, {:iri, "p"}, {:literal, "x"}, nil}])
      iex> {r.code, r.evidence.reason}
      {:REFUSED_INVALID_TERM_MAP, :blank_node}
  """

  alias AshR2RML.Refusal

  @xsd_string "http://www.w3.org/2001/XMLSchema#string"

  @type iri_term :: {:iri, String.t()}
  @type literal_term ::
          {:literal, String.t()}
          | {:literal, String.t(), {:datatype, String.t()} | {:lang, String.t()}}
  @type term_t :: iri_term() | literal_term()
  @type quad :: {iri_term(), iri_term(), term_t(), iri_term() | nil}

  @doc """
  Serializes quads to canonical N-Quads, or refuses on a blank node / invalid term.
  """
  @spec serialize([quad()]) :: {:ok, String.t()} | {:error, Refusal.t()}
  def serialize(quads) when is_list(quads) do
    with {:ok, lines} <- lines(quads) do
      {:ok, lines |> Enum.map(&[&1, ?\n]) |> IO.iodata_to_binary()}
    end
  end

  @doc """
  Like `serialize/1` but returns the sorted, de-duplicated lines (without newlines).
  """
  @spec lines([quad()]) :: {:ok, [String.t()]} | {:error, Refusal.t()}
  def lines(quads) when is_list(quads) do
    quads
    |> Enum.reduce_while({:ok, []}, fn quad, {:ok, acc} ->
      case line(quad) do
        {:ok, l} -> {:cont, {:ok, [l | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, acc |> Enum.uniq() |> Enum.sort()}
      err -> err
    end
  end

  @spec line(term()) :: {:ok, String.t()} | {:error, Refusal.t()}
  defp line({s, p, o, g}) do
    with {:ok, s} <- subject(s),
         {:ok, p} <- predicate(p),
         {:ok, o} <- object(o),
         {:ok, g} <- graph(g) do
      {:ok, ([s, p, o] ++ g ++ ["."]) |> Enum.intersperse(?\s) |> IO.iodata_to_binary()}
    end
  end

  defp line(other), do: refuse(:invalid_term, other)

  defp subject({:iri, _} = t), do: term(t)
  defp subject(t), do: refuse_term(t)

  defp predicate({:iri, _} = t), do: term(t)
  defp predicate(t), do: refuse_term(t)

  defp object(t), do: term(t)

  defp graph(nil), do: {:ok, []}

  defp graph({:iri, _} = t) do
    with {:ok, s} <- term(t), do: {:ok, [s]}
  end

  defp graph(t), do: refuse_term(t)

  defp term({:iri, iri} = t) when is_binary(iri) do
    if String.valid?(iri), do: {:ok, "<" <> escape_iri(iri) <> ">"}, else: refuse_term(t)
  end

  # Literal text must be valid UTF-8: escaping is byte-wise and would otherwise emit
  # an invalid N-Quads document without any refusal.
  defp term({:literal, lex} = t) when is_binary(lex), do: valid_literal(t, lex)
  defp term({:literal, lex, _} = t) when is_binary(lex), do: valid_literal(t, lex)
  defp term(t), do: refuse_term(t)

  defp valid_literal(t, lex) do
    if String.valid?(lex), do: literal(t), else: refuse_term(t)
  end

  defp literal({:literal, lex}), do: {:ok, quote_lit(lex)}
  defp literal({:literal, lex, {:datatype, @xsd_string}}), do: {:ok, quote_lit(lex)}

  defp literal({:literal, lex, {:datatype, dt}} = t) when is_binary(dt) do
    if String.valid?(dt),
      do: {:ok, quote_lit(lex) <> "^^<" <> escape_iri(dt) <> ">"},
      else: refuse_term(t)
  end

  defp literal({:literal, lex, {:lang, tag}} = t) when is_binary(tag) and tag != "" do
    if String.valid?(tag),
      do: {:ok, quote_lit(lex) <> "@" <> String.downcase(tag)},
      else: refuse_term(t)
  end

  defp literal(t), do: refuse_term(t)

  defp refuse_term({:bnode, _} = t), do: refuse(:blank_node, t)
  defp refuse_term(t), do: refuse(:invalid_term, t)

  defp refuse(:blank_node, t) do
    {:error,
     Refusal.new(
       :REFUSED_INVALID_TERM_MAP,
       t,
       "blank nodes are not permitted in canonical N-Quads output",
       %{reason: :blank_node}
     )}
  end

  defp refuse(:invalid_term, t) do
    {:error,
     Refusal.new(
       :REFUSED_INVALID_TERM_MAP,
       t,
       "term is not a valid IRI, literal, or graph position",
       %{reason: :invalid_term}
     )}
  end

  defp quote_lit(lex), do: "\"" <> escape_literal(lex) <> "\""

  defp escape_literal(s) do
    for <<c <- s>>, into: "" do
      case c do
        ?\\ -> "\\\\"
        ?" -> "\\\""
        ?\n -> "\\n"
        ?\r -> "\\r"
        _ -> <<c>>
      end
    end
  end

  defp escape_iri(s) do
    s
    |> String.to_charlist()
    |> Enum.map_join(&iri_char/1)
  end

  defp iri_char(c) when c <= 0x20 or c in ~c[<>"{}|^`\\], do: uescape(c)
  defp iri_char(c) when c in 0x7F..0x9F, do: uescape(c)
  defp iri_char(c), do: <<c::utf8>>

  defp uescape(c) do
    "\\u" <> String.pad_leading(Integer.to_string(c, 16), 4, "0")
  end
end
