# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OBDA.InMemory.GraphQuery do
  @moduledoc """
  Plans SPARQL `GRAPH` patterns for `AshR2RML.OBDA.InMemory`.

  SPARQL.ex parses `GRAPH` but cannot execute it, so the in-memory backend evaluates it
  against the materialized `RDF.Dataset` itself. Supported shape: exactly one
  `GRAPH <iri> { P }`, `GRAPH prefix:name { P }` or `GRAPH ?g { P }` that is the only
  content (besides `FILTER`s) of the top-level WHERE group.

    * IRI form -- `P` runs once against that named graph (an absent graph is empty).
    * Variable form -- `P` runs once per named graph with `BIND(<graph> AS ?g)` and the
      solutions are merged. Solution modifiers that would be wrong when applied per graph
      (LIMIT, OFFSET, ORDER BY, GROUP BY, DISTINCT, aggregates) are refused, not guessed.

  Anything else (several GRAPH clauses, GRAPH mixed with other patterns, nested GRAPH) is
  a typed refusal, never a silent partial answer.
  """

  # Regexes live in functions, not module attributes (OTP 28 compiled-regex rule).
  defp grapher, do: ~r/(?<![\w?$:.\-])GRAPH\s+(<i*>|[?$]\w+|[A-Za-z_][\w\-]*:[\w.\-]*)\s*\{/i

  defp modifiers do
    ~r/(?<![\w?$])(LIMIT|OFFSET|GROUP\s+BY|DISTINCT|REDUCED|ORDER\s+BY|HAVING|COUNT|SUM|AVG|MIN|MAX|SAMPLE|GROUP_CONCAT)(?![\w])/i
  end

  @type plan ::
          %{kind: :iri, iri: RDF.IRI.t(), rewritten: String.t()}
          | %{kind: :var, rewrite: (String.t() -> String.t())}

  @doc """
  Returns `:none` when the query has no GRAPH pattern, `{:ok, plan}` for a supported
  shape, or `{:error, message, evidence}`.

  ## Examples

      iex> AshR2RML.OBDA.InMemory.GraphQuery.plan("SELECT * WHERE { ?s ?p ?o }")
      :none

      iex> {:ok, plan} =
      ...>   AshR2RML.OBDA.InMemory.GraphQuery.plan("SELECT * WHERE { GRAPH <urn:uuid:5f1c2a64-0000-4000-8000-000000000001> { ?s ?p ?o } }")
      iex> {plan.kind, to_string(plan.iri)}
      {:iri, "urn:uuid:5f1c2a64-0000-4000-8000-000000000001"}
  """
  @spec plan(String.t()) :: :none | {:ok, plan()} | {:error, String.t(), map()}
  def plan(sparql) when is_binary(sparql) do
    masked = mask(sparql)

    case Regex.scan(grapher(), masked, return: :index) do
      [] -> :none
      [[whole, target]] -> plan_clause(sparql, masked, whole, target)
      many -> {:error, "only one GRAPH pattern per query is supported", %{graph_patterns: length(many)}}
    end
  end

  defp plan_clause(sparql, masked, {start, len}, {t_start, t_len}) do
    open = start + len - 1
    close = matching_close(masked, open)
    enclosing = enclosing_open(masked, start)
    target = binary_part(sparql, t_start, t_len)

    with {:ok, group_open} <- top_level_group(enclosing, start),
         group_close = matching_close(masked, group_open),
         :ok <- only_graph_in_group(masked, group_open, group_close, start, close),
         {:ok, kind} <- classify(sparql, masked, target) do
      build(kind, sparql, masked, {start, open, close})
    end
  end

  defp build({:iri, iri}, sparql, _masked, {start, open, close}) do
    rewritten =
      binary_part(sparql, 0, start) <>
        binary_part(sparql, open, close - open + 1) <>
        binary_part(sparql, close + 1, byte_size(sparql) - close - 1)

    {:ok, %{kind: :iri, iri: RDF.iri(iri), rewritten: rewritten}}
  end

  defp build({:var, var}, sparql, masked, {start, open, close}) do
    if Regex.match?(modifiers(), masked) do
      {:error, "GRAPH ?var cannot be combined with LIMIT/OFFSET/ORDER BY/GROUP BY/DISTINCT/aggregates",
       %{variable: var}}
    else
      head = binary_part(sparql, 0, start)
      inner = binary_part(sparql, open + 1, close - open - 1)
      tail = binary_part(sparql, close + 1, byte_size(sparql) - close - 1)

      rewrite = fn graph_iri -> head <> "{ " <> inner <> " BIND(<" <> graph_iri <> "> AS " <> var <> ") }" <> tail end
      {:ok, %{kind: :var, rewrite: rewrite}}
    end
  end

  defp classify(_sparql, _masked, "<" <> _ = target), do: {:ok, {:iri, String.slice(target, 1..-2//1)}}
  defp classify(_sparql, _masked, <<c, _::binary>> = target) when c in [??, ?$], do: {:ok, {:var, target}}

  defp classify(sparql, masked, prefixed) do
    [prefix, local] = String.split(prefixed, ":", parts: 2)

    case Enum.find(prefix_decls(sparql, masked), fn {name, _iri} -> name == prefix end) do
      {_, base} -> {:ok, {:iri, base <> local}}
      nil -> {:error, "GRAPH prefixed name uses an undeclared prefix", %{prefix: prefix}}
    end
  end

  defp prefix_decls(sparql, masked) do
    ~r/PREFIX\s+([\w\-]*):\s*(<i*>)/i
    |> Regex.scan(masked, return: :index)
    |> Enum.map(fn [_, {n_start, n_len}, {i_start, i_len}] ->
      {binary_part(sparql, n_start, n_len), binary_part(sparql, i_start + 1, i_len - 2)}
    end)
  end

  defp top_level_group({open, depth}, _start) when depth == 1, do: {:ok, open}

  defp top_level_group(_, _start),
    do: {:error, "GRAPH inside a nested group (OPTIONAL/UNION/MINUS/subquery) is unsupported", %{}}

  defp only_graph_in_group(masked, group_open, group_close, start, close) do
    before_clause = binary_part(masked, group_open + 1, start - group_open - 1)
    after_clause = binary_part(masked, close + 1, group_close - close - 1)
    rest = strip_filters(before_clause <> " " <> after_clause)

    if String.replace(rest, ~r/[\s.]/, "") == "" do
      :ok
    else
      {:error, "GRAPH mixed with other patterns in the same group is unsupported", %{remainder: String.trim(rest)}}
    end
  end

  # Removes `FILTER ( ... )` (balanced parentheses) from an already masked fragment.
  defp strip_filters(fragment) do
    case Regex.run(~r/FILTER\s*\(/i, fragment, return: :index) do
      nil ->
        fragment

      [{start, len}] ->
        open = start + len - 1
        close = matching(fragment, open, ?(, ?))

        binary_part(fragment, 0, start) <>
          " " <> strip_filters(binary_part(fragment, close + 1, byte_size(fragment) - close - 1))
    end
  end

  defp matching_close(text, open), do: matching(text, open, ?{, ?})

  # Index of the bracket closing the one at `open`; end of text when unbalanced.
  defp matching(text, open, opener, closer) do
    size = byte_size(text)

    Enum.reduce_while((open + 1)..(size - 1)//1, 1, fn index, depth ->
      case :binary.at(text, index) do
        ^opener -> {:cont, depth + 1}
        ^closer when depth == 1 -> {:halt, {:found, index}}
        ^closer -> {:cont, depth - 1}
        _ -> {:cont, depth}
      end
    end)
    |> case do
      {:found, index} -> index
      _ -> size - 1
    end
  end

  # `{index_of_innermost_open_brace, depth}` at byte `start` (depth 0 => no open group).
  defp enclosing_open(masked, start) do
    masked
    |> binary_part(0, start)
    |> :binary.bin_to_list()
    |> Enum.with_index()
    |> Enum.reduce([], fn
      {?{, index}, stack -> [index | stack]
      {?}, _index}, [_ | stack] -> stack
      _, stack -> stack
    end)
    |> case do
      [] -> {nil, 0}
      [innermost | _] = stack -> {innermost, length(stack)}
    end
  end

  # Same-length copy of `sparql` in which comments are blanked, string literals become
  # `"sss"` and IRIREFs become `<iii>`, so structural scans cannot be fooled by their content.
  defp mask(sparql), do: sparql |> mask([]) |> Enum.reverse() |> IO.iodata_to_binary()

  defp mask(<<>>, acc), do: acc

  defp mask(<<"#", rest::binary>>, acc) do
    {comment, remainder} = split_line(rest)
    mask(remainder, [String.duplicate(" ", byte_size(comment) + 1) | acc])
  end

  defp mask(<<q, rest::binary>>, acc) when q in [?", ?'] do
    {length, remainder} = skip_string(rest, q, 0)
    mask(remainder, [<<q>> <> String.duplicate("s", max(length - 1, 0)) <> closing(length, q) | acc])
  end

  defp mask(<<"<", rest::binary>> = whole, acc) do
    case Regex.run(~r/\A<([^\s<>"{}|^`\\]*)>/, whole) do
      [matched, inner] ->
        remainder = binary_part(rest, byte_size(matched) - 1, byte_size(rest) - byte_size(matched) + 1)
        mask(remainder, ["<" <> String.duplicate("i", byte_size(inner)) <> ">" | acc])

      nil ->
        mask(rest, ["<" | acc])
    end
  end

  defp mask(<<char, rest::binary>>, acc), do: mask(rest, [<<char>> | acc])

  defp closing(0, _q), do: ""
  defp closing(_length, q), do: <<q>>

  defp split_line(text) do
    case :binary.split(text, "\n") do
      [comment, remainder] -> {comment, "\n" <> remainder}
      [comment] -> {comment, ""}
    end
  end

  # Returns `{consumed_bytes_including_closing_quote, remainder}`.
  defp skip_string(<<>>, _q, count), do: {count, <<>>}
  defp skip_string(<<?\\, _escaped, rest::binary>>, q, count), do: skip_string(rest, q, count + 2)
  defp skip_string(<<q, rest::binary>>, q, count), do: {count + 1, rest}
  defp skip_string(<<_, rest::binary>>, q, count), do: skip_string(rest, q, count + 1)
end
