# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.POWL.WorkflowNet do
  @moduledoc """
  Formal implementation of Workflow Nets (WF-nets) and the structural decomposition
  algorithms (PartitionMG and PartitionSM) defined in Kourani et al. (2026).
  """

  defstruct [
    :source,
    :sink,
    places: MapSet.new(),
    transitions: MapSet.new(),
    labels: %{},
    preset: %{},
    postset: %{}
  ]

  @type place :: atom() | String.t()
  @type transition :: atom() | String.t()
  @type t :: %__MODULE__{
          source: place(),
          sink: place(),
          places: MapSet.t(place()),
          transitions: MapSet.t(transition()),
          labels: %{transition() => atom() | String.t()},
          preset: %{(place() | transition()) => MapSet.t()},
          postset: %{(place() | transition()) => MapSet.t()}
        }

  @doc "Builds a new Workflow Net from places, transitions, labels, and flow tuples."
  @spec new(place(), place(), [place()], [transition()], map(), [{any(), any()}]) :: t()
  def new(source, sink, places, transitions, labels, flow) do
    all_places = MapSet.new([source, sink | places])
    all_transitions = MapSet.new(transitions)

    preset =
      Enum.reduce(flow, %{}, fn {u, v}, acc ->
        Map.update(acc, v, MapSet.new([u]), &MapSet.put(&1, u))
      end)

    postset =
      Enum.reduce(flow, %{}, fn {u, v}, acc ->
        Map.update(acc, u, MapSet.new([v]), &MapSet.put(&1, v))
      end)

    %__MODULE__{
      source: source,
      sink: sink,
      places: all_places,
      transitions: all_transitions,
      labels: labels,
      preset: preset,
      postset: postset
    }
  end

  @doc "Pre-set •x of a node x"
  def preset(%__MODULE__{preset: ps}, x), do: Map.get(ps, x, MapSet.new())

  @doc "Post-set x• of a node x"
  def postset(%__MODULE__{postset: ps}, x), do: Map.get(ps, x, MapSet.new())

  @doc "Forward restricted reachability R_{\neg tstop}(p)"
  def forward_restricted_reachability(%__MODULE__{} = net, p, tstop) do
    traverse_forward(net, [p], tstop, MapSet.new(), MapSet.new())
  end

  defp traverse_forward(_net, [], _tstop, _visited, acc), do: acc

  defp traverse_forward(net, [curr | rest], tstop, visited, acc) do
    if MapSet.member?(visited, curr) or curr == tstop do
      traverse_forward(net, rest, tstop, visited, acc)
    else
      visited = MapSet.put(visited, curr)
      next_nodes = postset(net, curr) |> MapSet.to_list()

      acc =
        if MapSet.member?(net.transitions, curr) and curr != tstop do
          MapSet.put(acc, curr)
        else
          acc
        end

      traverse_forward(net, rest ++ next_nodes, tstop, visited, acc)
    end
  end

  @doc "Backward restricted reachability R_{\neg tstop}(p)"
  def backward_restricted_reachability(%__MODULE__{} = net, p, tstop) do
    traverse_backward(net, [p], tstop, MapSet.new(), MapSet.new())
  end

  defp traverse_backward(_net, [], _tstop, _visited, acc), do: acc

  defp traverse_backward(net, [curr | rest], tstop, visited, acc) do
    if MapSet.member?(visited, curr) or curr == tstop do
      traverse_backward(net, rest, tstop, visited, acc)
    else
      visited = MapSet.put(visited, curr)
      prev_nodes = preset(net, curr) |> MapSet.to_list()

      acc =
        if MapSet.member?(net.transitions, curr) and curr != tstop do
          MapSet.put(acc, curr)
        else
          acc
        end

      traverse_backward(net, rest ++ prev_nodes, tstop, visited, acc)
    end
  end

  @doc "Checks if node u can reach node v"
  def reachable?(%__MODULE__{} = net, u, v) do
    do_reachable(net, [u], v, MapSet.new())
  end

  defp do_reachable(_net, [], _target, _visited), do: false

  defp do_reachable(net, [curr | rest], target, visited) do
    if curr == target and MapSet.size(visited) > 0 do
      true
    else
      if MapSet.member?(visited, curr) do
        do_reachable(net, rest, target, visited)
      else
        visited = MapSet.put(visited, curr)
        next_nodes = postset(net, curr) |> MapSet.to_list()

        if target in next_nodes do
          true
        else
          do_reachable(net, rest ++ next_nodes, target, visited)
        end
      end
    end
  end

  @doc "Algorithm 1: Conflict-Hiding Partitioning (PartitionMG)"
  def partition_mg(%__MODULE__{} = net) do
    # Initial partition: one part per transition
    initial_parts = Enum.map(net.transitions, &MapSet.new([&1]))

    # Forward analysis: XOR-splits
    parts_after_splits =
      Enum.reduce(net.places, initial_parts, fn p, parts ->
        targets = postset(net, p) |> MapSet.to_list()

        if length(targets) > 1 do
          group =
            Enum.filter(net.transitions, fn t ->
              Enum.any?(targets, fn t1 ->
                Enum.any?(targets, fn t2 ->
                  t1 != t2 and reachable?(net, t1, t) and not reachable?(net, t2, t)
                end)
              end)
            end)
            |> MapSet.new()

          merge_overlapping_parts(parts, group)
        else
          parts
        end
      end)

    # Backward analysis: XOR-joins
    Enum.reduce(net.places, parts_after_splits, fn p, parts ->
      sources = preset(net, p) |> MapSet.to_list()

      if length(sources) > 1 do
        group =
          Enum.filter(net.transitions, fn t ->
            Enum.any?(sources, fn t1 ->
              Enum.any?(sources, fn t2 ->
                t1 != t2 and reachable?(net, t, t1) and not reachable?(net, t, t2)
              end)
            end)
          end)
          |> MapSet.new()

        merge_overlapping_parts(parts, group)
      else
        parts
      end
    end)
  end

  @doc "Algorithm 2: Concurrency-Hiding Partitioning (PartitionSM)"
  def partition_sm(%__MODULE__{} = net) do
    initial_parts = Enum.map(net.transitions, &MapSet.new([&1]))

    # Forward analysis: AND-splits
    parts_after_splits =
      Enum.reduce(net.transitions, initial_parts, fn tsplit, parts ->
        out_places = postset(net, tsplit) |> MapSet.to_list()

        if length(out_places) > 1 do
          threads =
            Enum.filter(net.transitions, fn t ->
              Enum.any?(out_places, fn p1 ->
                Enum.any?(out_places, fn p2 ->
                  p1 != p2 and
                    MapSet.member?(forward_restricted_reachability(net, p1, tsplit), t) and
                    not MapSet.member?(forward_restricted_reachability(net, p2, tsplit), t)
                end)
              end)
            end)

          group = MapSet.new([tsplit | threads])
          merge_overlapping_parts(parts, group)
        else
          parts
        end
      end)

    # Backward analysis: AND-joins
    Enum.reduce(net.transitions, parts_after_splits, fn tjoin, parts ->
      in_places = preset(net, tjoin) |> MapSet.to_list()

      if length(in_places) > 1 do
        threads =
          Enum.filter(net.transitions, fn t ->
            Enum.any?(in_places, fn p1 ->
              Enum.any?(in_places, fn p2 ->
                p1 != p2 and
                  MapSet.member?(backward_restricted_reachability(net, p1, tjoin), t) and
                  not MapSet.member?(backward_restricted_reachability(net, p2, tjoin), t)
              end)
            end)
          end)

        group = MapSet.new([tjoin | threads])
        merge_overlapping_parts(parts, group)
      else
        parts
      end
    end)
  end

  defp merge_overlapping_parts(parts, group) do
    if MapSet.size(group) <= 1 do
      parts
    else
      {overlapping, non_overlapping} =
        Enum.split_with(parts, fn part -> not MapSet.disjoint?(part, group) end)

      merged = Enum.reduce(overlapping, group, &MapSet.union/2)
      [merged | non_overlapping]
    end
  end

  @doc "Definition 4.3: Execution Order (Partial Order binary relation)"
  def execution_order(%__MODULE__{} = net, parts) do
    indexed_parts = Enum.with_index(parts)

    for {ti, i} <- indexed_parts,
        {tj, j} <- indexed_parts,
        i != j,
        dependency_exists?(net, ti, tj) do
      {i, j}
    end
    |> MapSet.new()
  end

  defp dependency_exists?(net, ti, tj) do
    # Check if there is any place p such that p in Ti▷ and p in ▷Tj
    exit_places_ti = Enum.flat_map(ti, &postset(net, &1)) |> MapSet.new()
    entry_places_tj = Enum.flat_map(tj, &preset(net, &1)) |> MapSet.new()
    not MapSet.disjoint?(exit_places_ti, entry_places_tj)
  end

  @doc "Definition 4.8: Execution Flow (Choice Graph edges with |> and [])"
  def execution_flow(%__MODULE__{} = net, parts) do
    indexed_parts = Enum.with_index(parts)

    internal_edges =
      for {ti, i} <- indexed_parts,
          {tj, j} <- indexed_parts,
          i != j,
          dependency_exists?(net, ti, tj) do
        {i, j}
      end

    start_edges =
      for {ti, i} <- indexed_parts,
          Enum.any?(ti, fn t -> MapSet.member?(preset(net, t), net.source) end) do
        {:start, i}
      end

    end_edges =
      for {ti, i} <- indexed_parts,
          Enum.any?(ti, fn t -> MapSet.member?(postset(net, t), net.sink) end) do
        {i, :end}
      end

    MapSet.new(internal_edges ++ start_edges ++ end_edges)
  end
end
