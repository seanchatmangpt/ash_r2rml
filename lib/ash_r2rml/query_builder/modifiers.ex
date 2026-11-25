# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.QueryBuilder.Modifiers do
  @moduledoc """
  SPARQL solution modifiers (`ORDER BY`, `LIMIT`, `OFFSET`) parsed from the query text and
  applied to projected binding rows.

  SPARQL.ex does not implement these modifiers, so `AshR2RML.OBDA` applies them itself.
  Parsing is deliberately strict: a tail it cannot fully account for (`GROUP BY`, `HAVING`,
  `VALUES`, `ORDER BY` over a function call) yields `:unparsed` and the rows are left untouched.

  ## Examples

      iex> sparql = "SELECT ?x WHERE { ?s ?p ?x } ORDER BY DESC(?x) ?s LIMIT 5 OFFSET 2"
      iex> AshR2RML.QueryBuilder.Modifiers.parse(sparql)
      {:ok, %{order: [{"x", :desc}, {"s", :asc}], limit: 5, offset: 2}}

      iex> AshR2RML.QueryBuilder.Modifiers.parse("SELECT ?x WHERE { ?s ?p ?x }")
      {:ok, %{order: [], limit: nil, offset: 0}}

      iex> AshR2RML.QueryBuilder.Modifiers.parse("SELECT ?x WHERE { ?s ?p ?x } GROUP BY ?x")
      :unparsed

      iex> rows = [%{"x" => 1}, %{"x" => 3}, %{"x" => 2}]
      iex> AshR2RML.QueryBuilder.Modifiers.run(rows, {:ok, %{order: [{"x", :desc}], limit: 2, offset: 0}})
      [%{"x" => 3}, %{"x" => 2}]
  """

  @type direction :: :asc | :desc
  @type t :: %{order: [{String.t(), direction()}], limit: non_neg_integer() | nil, offset: non_neg_integer()}

  @cond_regex ~r/(ASC|DESC)\s*\(\s*\?(\w+)\s*\)|\?(\w+)/i

  @doc "Parses the solution-modifier tail of `sparql`."
  @spec parse(String.t()) :: {:ok, t()} | :unparsed
  def parse(sparql) when is_binary(sparql) do
    case tail(sparql) do
      nil -> :unparsed
      tail -> parse_tail(tail)
    end
  end

  defp parse_tail(tail) do
    {order_src, rest} = split_order(tail)
    {limit, rest} = take_int(rest, ~r/\bLIMIT\s+(\d+)/i)
    {offset, rest} = take_int(rest, ~r/\bOFFSET\s+(\d+)/i)

    with true <- String.trim(rest) == "",
         {:ok, order} <- parse_order(order_src) do
      {:ok, %{order: order, limit: limit, offset: offset || 0}}
    else
      _ -> :unparsed
    end
  end

  @doc """
  Refuses a query whose modifier tail cannot be parsed but contains `ORDER BY`, `LIMIT`, `OFFSET`,
  `GROUP BY`, `HAVING` or `VALUES`, since `run/2` would otherwise silently return unsorted or
  untruncated rows.

  ## Examples

      iex> AshR2RML.QueryBuilder.Modifiers.check("SELECT ?x WHERE { ?s ?p ?x } ORDER BY DESC(?x) LIMIT 2")
      :ok

      iex> AshR2RML.QueryBuilder.Modifiers.check("SELECT ?x WHERE { ?s ?p ?x }")
      :ok

      iex> sparql = "SELECT ?x WHERE { ?s ?p ?x } ORDER BY STR(?x)"
      iex> {:error, %AshR2RML.Refusal{code: code}} = AshR2RML.QueryBuilder.Modifiers.check(sparql)
      iex> code
      :REFUSED_UNSUPPORTED_SPARQL_FEATURE

      iex> sparql = "SELECT ?x WHERE { ?s ?p ?x } ORDER BY STR(?x) LIMIT 2"
      iex> {:error, %AshR2RML.Refusal{code: code}} = AshR2RML.QueryBuilder.Modifiers.check(sparql)
      iex> code
      :REFUSED_UNSUPPORTED_SPARQL_FEATURE
  """
  @spec check(String.t()) :: :ok | {:error, AshR2RML.Refusal.t()}
  def check(sparql) when is_binary(sparql) do
    with :unparsed <- parse(sparql),
         tail when is_binary(tail) <- tail(sparql),
         true <- Regex.match?(~r/\b(?:ORDER\s+BY|LIMIT|OFFSET|GROUP\s+BY|HAVING|VALUES)\b/i, tail) do
      {:error,
       AshR2RML.Refusal.new(
         :REFUSED_UNSUPPORTED_SPARQL_FEATURE,
         "ORDER BY/LIMIT/OFFSET/GROUP BY/HAVING/VALUES",
         "an unsupported solution-modifier tail (ORDER BY over an expression, GROUP BY, HAVING, VALUES) " <>
           "cannot be applied",
         %{tail: String.trim(tail)}
       )}
    else
      _ -> :ok
    end
  end

  @doc "Applies parsed modifiers to binding rows: ORDER BY, then OFFSET, then LIMIT."
  @spec run([map()], {:ok, t()} | :unparsed) :: [map()]
  def run(rows, {:ok, %{order: order, limit: limit, offset: offset}}) when is_list(rows) do
    rows
    |> sort(order)
    |> Enum.drop(offset)
    |> take(limit)
  end

  def run(rows, _unparsed), do: rows

  defp take(rows, nil), do: rows
  defp take(rows, limit), do: Enum.take(rows, limit)

  @doc """
  Total order over normalized binding values: unbound first, then numbers (numeric), then
  strings (bytewise), then anything else by `inspect/1`.
  """
  @spec compare(term(), term()) :: :lt | :eq | :gt
  def compare(a, b) when a == b, do: :eq
  def compare(nil, _), do: :lt
  def compare(_, nil), do: :gt
  def compare(a, b) when is_number(a) and is_number(b), do: if(a < b, do: :lt, else: :gt)
  def compare(%Decimal{} = a, b) when is_number(b) or is_struct(b, Decimal), do: Decimal.compare(a, to_decimal(b))
  def compare(a, %Decimal{} = b) when is_number(a), do: Decimal.compare(to_decimal(a), b)
  def compare(a, b) when is_binary(a) and is_binary(b), do: if(a < b, do: :lt, else: :gt)

  def compare(%mod{} = a, %mod{} = b) when mod in [Date, Time, DateTime, NaiveDateTime],
    do: mod.compare(a, b)

  def compare(a, b) do
    case {rank(a), rank(b)} do
      {same, same} -> tie_break(a, b)
      {ra, rb} -> if ra < rb, do: :lt, else: :gt
    end
  end

  # `inspect/1` may collide for distinct terms; Erlang term order keeps the order antisymmetric.
  defp tie_break(a, b) do
    {ia, ib} = {inspect(a), inspect(b)}

    cond do
      ia < ib -> :lt
      ia > ib -> :gt
      a < b -> :lt
      true -> :gt
    end
  end

  defp rank(%RDF.IRI{}), do: 0
  defp rank(v) when is_number(v) or is_struct(v, Decimal), do: 1
  defp rank(v) when is_binary(v), do: 2
  defp rank(_), do: 3

  defp to_decimal(%Decimal{} = d), do: d
  defp to_decimal(n) when is_integer(n), do: Decimal.new(n)
  defp to_decimal(n) when is_float(n), do: Decimal.from_float(n)

  defp sort(rows, []), do: rows

  defp sort(rows, order) do
    # An ORDER BY variable that is not projected is absent from every row; it cannot be applied.
    order
    |> Enum.filter(fn {var, _dir} -> Enum.any?(rows, &Map.has_key?(&1, var)) end)
    |> sort_by_present(rows)
  end

  defp sort_by_present([], rows), do: rows

  defp sort_by_present(order, rows),
    do: Enum.sort(rows, fn a, b -> compare_rows(a, b, order) != :gt end)

  defp compare_rows(a, b, order) do
    Enum.reduce_while(order, :eq, fn {var, dir}, :eq ->
      case compare(Map.get(a, var), Map.get(b, var)) do
        :eq -> {:cont, :eq}
        result -> {:halt, if(dir == :desc, do: flip(result), else: result)}
      end
    end)
  end

  defp flip(:lt), do: :gt
  defp flip(:gt), do: :lt

  # Text after the last closing brace, with IRIs, string literals and comments removed so a
  # brace inside any of them cannot move the split point.
  defp tail(sparql) do
    stripped =
      sparql
      |> String.replace(~r/<[^<>"{}|^`\\\s]*>/, "<I>")
      |> String.replace(~r/"""(?:[^\\]|\\.)*?"""|'''(?:[^\\]|\\.)*?'''/s, "\"S\"")
      |> String.replace(~r/"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'/s, "\"S\"")
      |> String.replace(~r/#[^\n]*/, "")

    case :binary.matches(stripped, "}") do
      [] ->
        nil

      matches ->
        {pos, 1} = List.last(matches)
        binary_part(stripped, pos + 1, byte_size(stripped) - pos - 1)
    end
  end

  defp split_order(tail) do
    case Regex.run(~r/\bORDER\s+BY\b(.*?)(?=\bLIMIT\b|\bOFFSET\b|\z)/is, tail) do
      [whole, conds] -> {conds, String.replace(tail, whole, "", global: false)}
      nil -> {nil, tail}
    end
  end

  defp take_int(text, regex) do
    case Regex.run(regex, text) do
      [whole, n] -> {String.to_integer(n), String.replace(text, whole, "", global: false)}
      nil -> {nil, text}
    end
  end

  defp parse_order(nil), do: {:ok, []}

  defp parse_order(src) do
    conds = Regex.scan(@cond_regex, src)
    leftover = Regex.replace(@cond_regex, src, "")

    if conds == [] or String.trim(leftover) != "" do
      :error
    else
      {:ok, Enum.map(conds, &order_condition/1)}
    end
  end

  defp order_condition([_, dir, var]), do: {var, direction(dir)}
  defp order_condition([_, _, _, var]), do: {var, :asc}

  defp direction(dir), do: if(String.upcase(dir) == "DESC", do: :desc, else: :asc)
end
