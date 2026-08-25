# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Mix.SemanticTypes do
  @moduledoc false

  def load_source([]), do: Mix.raise("expected a semantic profile path, JSON document, or public IRI")

  def load_source(args) do
    source = Enum.join(args, " ")

    if length(args) == 1 and File.regular?(hd(args)) do
      case File.read(hd(args)) do
        {:ok, content} -> content
        {:error, reason} -> Mix.raise("cannot read #{hd(args)}: #{inspect(reason)}")
      end
    else
      source
    end
  end

  def load_json(path) do
    with {:ok, content} <- File.read(path), {:ok, value} <- Jason.decode(content) do
      value
    else
      {:error, reason} -> Mix.raise("cannot decode #{path}: #{inspect(reason)}")
    end
  end

  def plan!(args) do
    case AshR2RML.SemanticTypes.plan(load_source(args)) do
      {:ok, plan} -> plan
      {:error, refusals} -> Mix.raise(format_refusals(refusals))
    end
  end

  def print_json(value), do: value |> json_term() |> Jason.encode!(pretty: true) |> Mix.shell().info()
  def format_refusals(refusals), do: Enum.map_join(List.wrap(refusals), "\n", &"#{&1.code}: #{&1.detail}")

  defp json_term(%_{} = struct), do: struct |> Map.from_struct() |> json_term()
  defp json_term(map) when is_map(map), do: Map.new(map, fn {key, value} -> {json_key(key), json_term(value)} end)
  defp json_term(list) when is_list(list), do: Enum.map(list, &json_term/1)
  defp json_term(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> Enum.map(&json_term/1)
  defp json_term(value) when value in [true, false, nil], do: value
  defp json_term(value) when is_atom(value), do: Atom.to_string(value)
  defp json_term(value) when is_binary(value) or is_number(value), do: value
  defp json_term(value), do: inspect(value)
  defp json_key(key) when is_atom(key), do: Atom.to_string(key)
  defp json_key(key) when is_binary(key), do: key
  defp json_key(key), do: inspect(key)
end

defmodule Mix.Tasks.AshR2rml.Types.Plan do
  use Mix.Task
  @shortdoc "Plans public-ontology semantic type projections without writing files"
  @impl Mix.Task
  def run(args),
    do:
      args
      |> AshR2RML.Mix.SemanticTypes.plan!()
      |> AshR2RML.SemanticTypes.manifest()
      |> AshR2RML.Mix.SemanticTypes.print_json()
end

defmodule Mix.Tasks.AshR2rml.Types.Inspect do
  use Mix.Task
  @shortdoc "Inspects admitted semantic types for one or more public IRIs"
  @impl Mix.Task
  def run([]), do: Mix.raise("expected one or more public semantic type IRIs")

  def run(args) do
    case AshR2RML.SemanticTypes.plan(args) do
      {:ok, plan} -> AshR2RML.Mix.SemanticTypes.print_json(AshR2RML.SemanticTypes.manifest(plan))
      {:error, refusals} -> Mix.raise(AshR2RML.Mix.SemanticTypes.format_refusals(refusals))
    end
  end
end

defmodule Mix.Tasks.AshR2rml.Types.Manifest do
  use Mix.Task
  @shortdoc "Emits the stable semantic-type-plan JSON manifest"
  @impl Mix.Task
  def run(args),
    do:
      args
      |> AshR2RML.Mix.SemanticTypes.plan!()
      |> AshR2RML.SemanticTypes.manifest()
      |> AshR2RML.Mix.SemanticTypes.print_json()
end

defmodule Mix.Tasks.AshR2rml.Types.Verify do
  use Mix.Task
  @shortdoc "Verifies a semantic type plan and reports bounded standing"
  @impl Mix.Task
  def run(args) do
    plan = AshR2RML.Mix.SemanticTypes.plan!(args)

    case AshR2RML.SemanticTypes.verify(plan) do
      :ok ->
        AshR2RML.Mix.SemanticTypes.print_json(%{
          status: :PARTIAL_ALIVE,
          standing: :construct_only,
          plan_id: plan.id,
          verified_types: length(plan.types)
        })

      {:error, refusals} ->
        Mix.raise(AshR2RML.Mix.SemanticTypes.format_refusals(refusals))
    end
  end
end

defmodule Mix.Tasks.AshR2rml.Types.Check do
  use Mix.Task
  @shortdoc "Alias for ash_r2rml.types.verify"
  @impl Mix.Task
  def run(args), do: Mix.Task.run("ash_r2rml.types.verify", args)
end

defmodule Mix.Tasks.AshR2rml.Types.Diff do
  use Mix.Task
  @shortdoc "Diffs an admitted semantic manifest against an observed Ash manifest"
  @impl Mix.Task
  def run([expected, observed]) do
    expected = AshR2RML.Mix.SemanticTypes.load_json(expected)
    observed = AshR2RML.Mix.SemanticTypes.load_json(observed)
    expected |> AshR2RML.SemanticTypes.diff(observed) |> AshR2RML.Mix.SemanticTypes.print_json()
  end

  def run(_), do: Mix.raise("usage: mix ash_r2rml.types.diff EXPECTED.json OBSERVED.json")
end

defmodule Mix.Tasks.AshR2rml.Types.Sync do
  use Mix.Task
  @shortdoc "Runs the Igniter semantic type generator/synchronizer"
  @impl Mix.Task
  def run(args), do: Mix.Task.run("ash_r2rml.gen.semantic_types", args)
end
