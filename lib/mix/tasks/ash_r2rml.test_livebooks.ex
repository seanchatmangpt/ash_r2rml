# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.AshR2rml.TestLivebooks do
  @shortdoc "Executes explicitly marked Elixir cells in checked-in Livebooks"

  @moduledoc """
  Executes checked-in `.livemd` files as project-bound executable specifications.

  A cell participates only when the standard Elixir fence is immediately
  preceded by the marker:

      <!-- ash_r2rml:test -->
      ```elixir
      # assertions / public API exercise
      ```

  The evaluator preserves Elixir bindings across marked cells in the same
  notebook, fails on exceptions/assertion failures, and never requires Livebook
  as a runtime dependency. Unmarked notebooks remain ordinary documentation.

  Pass explicit paths to execute only those notebooks; with no arguments the
  task scans the repository root and `documentation/**` for `.livemd` files.
  """

  use Mix.Task

  @marker ~r/<!--\s*ash_r2rml:test\s*-->\s*```elixir\s*\n(.*?)```/ms

  @impl Mix.Task
  def run(paths) do
    Mix.Task.run("app.start")

    paths = if paths == [], do: discover(), else: paths

    results = Enum.map(paths, &{&1, run_file(&1)})
    executed = Enum.count(results, fn {_path, result} -> match?({:ok, _}, result) end)

    failures =
      Enum.filter(results, fn {_path, result} ->
        match?({:error, _}, result)
      end)

    if failures == [] do
      Mix.shell().info("Livebook executable specifications: #{executed} notebook(s) executed")
      :ok
    else
      message =
        failures
        |> Enum.map_join("\n\n", fn {path, {:error, failure}} ->
          "#{path}:\n#{failure}"
        end)

      Mix.raise("Livebook executable specification failure(s):\n\n#{message}")
    end
  end

  @doc "Execute all marked cells in one Livebook, preserving bindings between cells."
  @spec run_file(Path.t()) :: {:ok, map()} | :skip | {:error, String.t()}
  def run_file(path) do
    with {:ok, source} <- File.read(path) do
      cells =
        Regex.scan(@marker, source, capture: :all_but_first)
        |> Enum.map(&hd/1)

      case cells do
        [] ->
          :skip

        _ ->
          evaluate_cells(path, cells)
      end
    else
      {:error, reason} -> {:error, "cannot read notebook: #{inspect(reason)}"}
    end
  end

  defp discover do
    (Path.wildcard("*.livemd") ++ Path.wildcard("documentation/**/*.livemd"))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp evaluate_cells(path, cells) do
    cells
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, [], []}, fn {code, index}, {:ok, binding, results} ->
      try do
        {result, next_binding} = Code.eval_string(code, binding, file: path)
        {:cont, {:ok, next_binding, [result | results]}}
      rescue
        exception ->
          {:halt,
           {:error,
            "cell #{index} raised #{inspect(exception.__struct__)}: #{Exception.message(exception)}\n" <>
              Exception.format_stacktrace(__STACKTRACE__)}}
      catch
        kind, reason ->
          {:halt, {:error, "cell #{index} #{kind}: #{inspect(reason)}"}}
      end
    end)
    |> case do
      {:ok, _binding, results} ->
        {:ok, %{cells: length(cells), results: Enum.reverse(results)}}

      {:error, _} = error ->
        error
    end
  end
end
