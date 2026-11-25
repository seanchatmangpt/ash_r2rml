# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.QueryBuilder.Verification do
  @moduledoc """
  Post-read soundness check of a limited pushdown (see `AshR2RML.QueryBuilder.Lowering`).

  A narrowed read (`sort` plus `limit = keep + 1`) is only trusted when the materialized graph
  proves it cannot have dropped a solution: join starvation, a tie at the boundary or an
  untyped key literal all request a full re-read (`:fallback`).
  """

  alias AshR2RML.QueryBuilder.{Modifiers, Pushdown}

  @doc """
  Decides whether a limited pushdown's result can be trusted.

  `graph` is the graph materialized from the (possibly narrowed) read and `solution_count` the
  number of solutions SPARQL.ex produced over it. Returns `:ok` when the read provably saw every
  root row (`fewer than fetch` rows, or more, meaning the receiver did not narrow) or when it
  was truncated at `fetch` rows, produced at least `keep` solutions, and the sort key of row
  `keep` differs from that of the sentinel row `keep + 1`. Returns `:fallback` otherwise,
  including when a key literal is not typed as the mapping declares.
  """
  @spec verify(Pushdown.t(), RDF.Graph.t(), non_neg_integer()) :: :ok | :fallback
  def verify(%Pushdown{fetch: nil}, _graph, _solution_count), do: :ok

  def verify(%Pushdown{keys: keys, mapping: mapping, keep: keep, fetch: fetch}, graph, solution_count) do
    case root_key_rows(graph, mapping, keys) do
      {:ok, rows} -> decide(rows, keys, keep, fetch, solution_count)
      :error -> :fallback
    end
  rescue
    _ -> :fallback
  end

  defp decide(rows, keys, keep, fetch, solution_count) do
    n = length(rows)

    cond do
      # fewer rows than fetch: the read was exhaustive; more: the receiver did not narrow it
      n != fetch -> :ok
      solution_count < keep -> :fallback
      true -> tie_check(rows, keys, keep)
    end
  end

  defp tie_check(rows, keys, keep) do
    sorted = Enum.sort(rows, fn a, b -> compare_keys(a, b, keys) != :gt end)

    if compare_keys(Enum.at(sorted, keep - 1), Enum.at(sorted, keep), keys) == :eq,
      do: :fallback,
      else: :ok
  end

  defp compare_keys(a, b, keys) do
    [a, b, keys]
    |> Enum.zip()
    |> Enum.reduce_while(:eq, fn {x, y, %{dir: dir}}, :eq ->
      case Modifiers.compare(x, y) do
        :eq -> {:cont, :eq}
        :lt -> {:halt, if(dir == :desc, do: :gt, else: :lt)}
        :gt -> {:halt, if(dir == :desc, do: :lt, else: :gt)}
      end
    end)
  end

  defp root_key_rows(graph, mapping, keys) do
    graph
    |> RDF.Graph.subjects()
    |> Enum.filter(&root_subject?(mapping, &1))
    |> Enum.reduce_while({:ok, []}, fn subject, {:ok, acc} ->
      case key_values(graph, subject, keys) do
        {:ok, values} -> {:cont, {:ok, [values | acc]}}
        :error -> {:halt, :error}
      end
    end)
  end

  defp root_subject?(mapping, %RDF.IRI{} = subject) do
    match?({:ok, keys} when map_size(keys) > 0, AshR2RML.Subject.from_iri(mapping, RDF.IRI.to_string(subject)))
  end

  defp root_subject?(_mapping, _subject), do: false

  defp key_values(graph, subject, keys) do
    description = graph[subject]

    keys
    |> Enum.reduce_while({:ok, []}, fn key, {:ok, acc} ->
      case key_value(description, key) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      :error -> :error
    end
  end

  defp key_value(description, %{predicate: predicate, datatype: datatype}) do
    with [%RDF.Literal{} = literal] <- RDF.Description.get(description, RDF.iri(predicate)),
         true <- literal |> RDF.Literal.datatype_id() |> RDF.IRI.to_string() == datatype do
      {:ok, RDF.Literal.value(literal)}
    else
      _ -> :error
    end
  end
end
