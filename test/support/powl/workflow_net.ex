# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.POWL.WorkflowNet do
  @moduledoc """
  Formal implementation of Workflow Nets (WF-nets), structural decomposition
  algorithms (PartitionMG and PartitionSM), and mathematical soundness verifiers
  defined in Kourani, Park, and van der Aalst (arXiv:2602.15739v3, 2026).

  Structural Conditions (Definition 3.3):
  1. Bipartite graph over disjoint sets P (places) and T (transitions).
  2. Unique source place: {source} = {p ∈ P | •p = ∅}.
  3. Unique sink place: {sink} = {p ∈ P | p• = ∅}.
  4. Non-empty presets and postsets for all transitions: •t ≠ ∅ and t• ≠ ∅.
  5. Connectivity: every node x ∈ P ∪ T is on a directed path from source to sink.

  1-Safe Soundness Conditions (Definition 3.5):
  1. No dead transitions: each transition t ∈ T is enabled in at least one reachable marking.
  2. Option to complete: for every reachable marking M ∈ [M0⟩, [Mend] = [sink] is reachable from M.
  3. Proper completion: for every reachable marking M ∈ [M0⟩, sink ∈ M ⟹ M = [sink].
  4. 1-Safety: for every reachable marking M ∈ [M0⟩ and place p ∈ P, M(p) ≤ 1.
  5. Boundedness & deadlock/livelock cutoffs to avoid infinite state explosion.
  """

  alias AshR2RML.Refusal

  defstruct [
    :source,
    :sink,
    places: MapSet.new(),
    transitions: MapSet.new(),
    labels: %{},
    preset: %{},
    postset: %{},
    flow: []
  ]

  @type place :: atom() | String.t()
  @type transition :: atom() | String.t()
  @type marking :: %{place() => pos_integer()}
  @type t :: %__MODULE__{
          source: place(),
          sink: place(),
          places: MapSet.t(place()),
          transitions: MapSet.t(transition()),
          labels: %{transition() => atom() | String.t()},
          preset: %{(place() | transition()) => MapSet.t()},
          postset: %{(place() | transition()) => MapSet.t()},
          flow: [{any(), any()}]
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
      postset: postset,
      flow: flow
    }
  end

  @doc "Pre-set •x of a node x"
  def preset(%__MODULE__{preset: ps}, x), do: Map.get(ps, x, MapSet.new())

  @doc "Post-set x• of a node x"
  def postset(%__MODULE__{postset: ps}, x), do: Map.get(ps, x, MapSet.new())

  @doc """
  Checks if the Petri net graph is strictly bipartite:
  - P and T are disjoint: P ∩ T = ∅
  - Every edge (u, v) is in (P × T) ∪ (T × P)
  """
  @spec bipartite?(t()) :: boolean()
  def bipartite?(%__MODULE__{} = net) do
    disjoint? = MapSet.disjoint?(net.places, net.transitions)

    edges_valid? =
      Enum.all?(net.flow, fn {u, v} ->
        (MapSet.member?(net.places, u) and MapSet.member?(net.transitions, v)) or
          (MapSet.member?(net.transitions, u) and MapSet.member?(net.places, v))
      end)

    disjoint? and edges_valid?
  end

  @doc """
  Definition 3.3: Verifies formal Workflow Net structural preconditions:
  1. Disjointness of places P and transitions T.
  2. Bipartite flow: no place->place or transition->transition edges; all flow nodes in P ∪ T.
  3. Unique source place: {source} = {p in P | •p = ∅} with source ∈ P.
  4. Unique sink place: {sink} = {p in P | p• = ∅} with sink ∈ P.
  5. Non-empty presets and postsets for all transitions.
  6. Connectivity: every node is on a path from source to sink.
  """
  @spec verify_structure(t()) :: :ok | {:error, Refusal.t()}
  def verify_structure(%__MODULE__{} = net) do
    overlap = MapSet.intersection(net.places, net.transitions)

    cond do
      MapSet.size(overlap) > 0 ->
        {:error,
         Refusal.new(
           :REFUSED_INVALID_WORKFLOW_NET,
           :powl,
           "Places and transitions must be disjoint sets, overlapping nodes: #{inspect(MapSet.to_list(overlap))}",
           %{overlapping_nodes: MapSet.to_list(overlap)}
         )}

      not net_nodes_exist_in_flow?(net) ->
        invalid_edges = find_invalid_edges(net)

        {:error,
         Refusal.new(
           :REFUSED_INVALID_WORKFLOW_NET,
           :powl,
           "Flow contains invalid or non-bipartite edges: #{inspect(invalid_edges)}",
           %{invalid_edges: invalid_edges}
         )}

      not MapSet.member?(net.places, net.source) ->
        {:error,
         Refusal.new(
           :REFUSED_INVALID_WORKFLOW_NET,
           :powl,
           "Designated source place #{inspect(net.source)} is not in places set",
           %{source: net.source}
         )}

      not MapSet.member?(net.places, net.sink) ->
        {:error,
         Refusal.new(
           :REFUSED_INVALID_WORKFLOW_NET,
           :powl,
           "Designated sink place #{inspect(net.sink)} is not in places set",
           %{sink: net.sink}
         )}

      true ->
        verify_source_sink_and_connectivity(net)
    end
  end

  defp verify_source_sink_and_connectivity(%__MODULE__{} = net) do
    sources = Enum.filter(net.places, fn p -> MapSet.size(preset(net, p)) == 0 end)
    sinks = Enum.filter(net.places, fn p -> MapSet.size(postset(net, p)) == 0 end)

    orphan_trans_in = Enum.filter(net.transitions, fn t -> MapSet.size(preset(net, t)) == 0 end)
    orphan_trans_out = Enum.filter(net.transitions, fn t -> MapSet.size(postset(net, t)) == 0 end)

    cond do
      sources != [net.source] ->
        {:error,
         Refusal.new(
           :REFUSED_INVALID_WORKFLOW_NET,
           :powl,
           "Expected unique source place #{inspect(net.source)}, but found: #{inspect(sources)}",
           %{sources: sources, expected: net.source}
         )}

      sinks != [net.sink] ->
        {:error,
         Refusal.new(
           :REFUSED_INVALID_WORKFLOW_NET,
           :powl,
           "Expected unique sink place #{inspect(net.sink)}, but found: #{inspect(sinks)}",
           %{sinks: sinks, expected: net.sink}
         )}

      orphan_trans_in != [] ->
        {:error,
         Refusal.new(
           :REFUSED_INVALID_WORKFLOW_NET,
           :powl,
           "Transitions must have non-empty presets, found transitions with empty preset: #{inspect(orphan_trans_in)}",
           %{transitions_without_preset: orphan_trans_in}
         )}

      orphan_trans_out != [] ->
        {:error,
         Refusal.new(
           :REFUSED_INVALID_WORKFLOW_NET,
           :powl,
           "Transitions must have non-empty postsets, found transitions with empty postset: #{inspect(orphan_trans_out)}",
           %{transitions_without_postset: orphan_trans_out}
         )}

      not all_nodes_connected?(net) ->
        disconnected = find_disconnected_nodes(net)

        {:error,
         Refusal.new(
           :REFUSED_INVALID_WORKFLOW_NET,
           :powl,
           "Disconnected nodes detected in workflow net: #{inspect(disconnected)}",
           %{disconnected_nodes: disconnected}
         )}

      true ->
        :ok
    end
  end

  defp net_nodes_exist_in_flow?(%__MODULE__{} = net) do
    Enum.all?(net.flow, fn {u, v} ->
      (MapSet.member?(net.places, u) and MapSet.member?(net.transitions, v)) or
        (MapSet.member?(net.transitions, u) and MapSet.member?(net.places, v))
    end)
  end

  defp find_invalid_edges(%__MODULE__{} = net) do
    Enum.reject(net.flow, fn {u, v} ->
      (MapSet.member?(net.places, u) and MapSet.member?(net.transitions, v)) or
        (MapSet.member?(net.transitions, u) and MapSet.member?(net.places, v))
    end)
  end

  defp all_nodes_connected?(%__MODULE__{} = net) do
    find_disconnected_nodes(net) == []
  end

  defp find_disconnected_nodes(%__MODULE__{} = net) do
    all_nodes = MapSet.to_list(MapSet.union(net.places, net.transitions))

    Enum.reject(all_nodes, fn node ->
      (node == net.source or reachable?(net, net.source, node)) and
        (node == net.sink or reachable?(net, node, net.sink))
    end)
  end

  @doc "Definition 3.10: State Machine check (|•t| <= 1 and |t•| <= 1 for all t)"
  def state_machine?(%__MODULE__{} = net) do
    Enum.all?(net.transitions, fn t ->
      MapSet.size(preset(net, t)) <= 1 and MapSet.size(postset(net, t)) <= 1
    end)
  end

  @doc "Definition 3.11: Marked Graph check (|•p| <= 1 and |p•| <= 1 for all p)"
  def marked_graph?(%__MODULE__{} = net) do
    Enum.all?(net.places, fn p ->
      MapSet.size(preset(net, p)) <= 1 and MapSet.size(postset(net, p)) <= 1
    end)
  end

  @doc """
  Definition 3.5: Mathematical 1-Safe Soundness Verification:
  1. 1-Safety: in all reachable markings M, no place contains more than 1 token.
  2. No dead transitions: each transition t ∈ T is enabled in at least one reachable marking.
  3. Proper completion: [sink] is the ONLY reachable marking containing a token in the sink place.
  4. Option to complete: every reachable marking can reach the terminal marking [sink].
  5. Detection of reachable deadlocks (stuck non-sink states) and livelocks (inescapable cycles).
  6. State space explosion bounds (max_markings cutoff).

  Options:
  - `:max_markings` (default 5000)
  - `:max_depth` (default 200)
  """
  @spec verify_soundness(t(), keyword()) :: :ok | {:error, Refusal.t()}
  def verify_soundness(%__MODULE__{} = net, opts \\ []) do
    max_markings = Keyword.get(opts, :max_markings, 5000)
    max_depth = Keyword.get(opts, :max_depth, 200)

    initial_marking = %{net.source => 1}
    target_end_marking = %{net.sink => 1}

    case explore_marking_graph(net, initial_marking, max_markings, max_depth) do
      {:error, reason} ->
        {:error, reason}

      {:ok, %{visited: visited, graph: graph, enabled_transitions: enabled_transitions}} ->
        evaluate_soundness_properties(net, visited, graph, enabled_transitions, target_end_marking)
    end
  end

  # Firing and Reachability Engine with 1-safe multiset markings

  defp marking_enabled?(net, t, %{} = marking) do
    in_places = preset(net, t)
    Enum.all?(in_places, fn p -> Map.get(marking, p, 0) >= 1 end)
  end

  defp fire_transition(net, t, %{} = marking) do
    in_places = preset(net, t)
    out_places = postset(net, t)

    # Decrement preset places
    after_decrement =
      Enum.reduce(in_places, marking, fn p, acc ->
        count = Map.get(acc, p, 1) - 1
        if count <= 0, do: Map.delete(acc, p), else: Map.put(acc, p, count)
      end)

    # Increment postset places
    after_increment =
      Enum.reduce(out_places, after_decrement, fn p, acc ->
        Map.update(acc, p, 1, &(&1 + 1))
      end)

    after_increment
  end

  defp explore_marking_graph(net, initial_marking, max_markings, max_depth) do
    initial_queue = :queue.from_list([{initial_marking, 0}])
    visited = MapSet.new([initial_marking])
    graph = %{}
    enabled_transitions = MapSet.new()

    do_explore(
      net,
      initial_queue,
      visited,
      graph,
      enabled_transitions,
      max_markings,
      max_depth
    )
  end

  defp do_explore(
         net,
         queue,
         visited,
         graph,
         enabled_transitions,
         max_markings,
         max_depth
       ) do
    case :queue.out(queue) do
      {:empty, _queue} ->
        {:ok,
         %{
           visited: visited,
           graph: graph,
           enabled_transitions: enabled_transitions
         }}

      {{:value, {curr_marking, depth}}, rest_queue} ->
        # 1-Safety check on current marking
        unsafe_place = Enum.find(curr_marking, fn {_p, count} -> count > 1 end)

        if unsafe_place != nil do
          {p, count} = unsafe_place

          {:error,
           Refusal.new(
             :REFUSED_UNSOUND_WORKFLOW_NET,
             :powl,
             "1-Safety violated: place #{inspect(p)} accumulated #{count} tokens in marking #{inspect(curr_marking)}",
             %{place: p, token_count: count, marking: curr_marking}
           )}
        else
          enabled = Enum.filter(net.transitions, fn t -> marking_enabled?(net, t, curr_marking) end)
          new_enabled_transitions = MapSet.union(enabled_transitions, MapSet.new(enabled))

          successors =
            Enum.map(enabled, fn t ->
              next_m = fire_transition(net, t, curr_marking)
              {t, next_m}
            end)

          new_graph = Map.put(graph, curr_marking, successors)

          # Enqueue new markings if within depth
          {updated_queue, updated_visited, overflow?} =
            Enum.reduce_while(successors, {rest_queue, visited, false}, fn {_t, next_m}, {q, vis, _} ->
              if MapSet.member?(vis, next_m) do
                {:cont, {q, vis, false}}
              else
                if MapSet.size(vis) >= max_markings do
                  {:halt, {q, vis, true}}
                else
                  new_vis = MapSet.put(vis, next_m)
                  new_q = if depth < max_depth, do: :queue.in({next_m, depth + 1}, q), else: q
                  {:cont, {new_q, new_vis, false}}
                end
              end
            end)

          if overflow? do
            {:error,
             Refusal.new(
               :REFUSED_UNSOUND_WORKFLOW_NET,
               :powl,
               "State explosion: reachable state space exceeded limit of #{max_markings} markings",
               %{cutoff: :max_markings, limit: max_markings}
             )}
          else
            do_explore(
              net,
              updated_queue,
              updated_visited,
              new_graph,
              new_enabled_transitions,
              max_markings,
              max_depth
            )
          end
        end
    end
  end

  defp evaluate_soundness_properties(net, visited, graph, enabled_transitions, target_end_marking) do
    # 1. No dead transitions check
    dead_transitions = MapSet.difference(net.transitions, enabled_transitions)

    # 2. Proper completion check: any marking containing sink must be exactly target_end_marking
    improper_markings =
      Enum.filter(visited, fn m ->
        Map.get(m, net.sink, 0) > 0 and m != target_end_marking
      end)

    # 3. Option to complete: backward reachability from target_end_marking
    can_reach_end = compute_backward_reachability(visited, graph, target_end_marking)
    unreachable_from = MapSet.difference(visited, can_reach_end)

    cond do
      MapSet.size(dead_transitions) > 0 ->
        {:error,
         Refusal.new(
           :REFUSED_UNSOUND_WORKFLOW_NET,
           :powl,
           "Dead transitions detected in workflow net: #{inspect(MapSet.to_list(dead_transitions))}",
           %{dead_transitions: MapSet.to_list(dead_transitions)}
         )}

      length(improper_markings) > 0 ->
        first_improper = hd(improper_markings)

        {:error,
         Refusal.new(
           :REFUSED_UNSOUND_WORKFLOW_NET,
           :powl,
           "Improper completion detected: marking #{inspect(first_improper)} contains sink token while tokens remain on other places",
           %{improper_marking: first_improper, all_improper: improper_markings}
         )}

      MapSet.size(unreachable_from) > 0 ->
        # Classify the unreachable marking into deadlock or livelock
        unreachable_list = MapSet.to_list(unreachable_from)
        deadlock = Enum.find(unreachable_list, fn m -> Map.get(graph, m, []) == [] end)

        if deadlock != nil do
          {:error,
           Refusal.new(
             :REFUSED_UNSOUND_WORKFLOW_NET,
             :powl,
             "Reachable deadlock detected: marking #{inspect(deadlock)} has no enabled transitions and cannot reach sink",
             %{deadlock_marking: deadlock, non_completing_count: length(unreachable_list)}
           )}
        else
          first_livelock = hd(unreachable_list)

          {:error,
           Refusal.new(
             :REFUSED_UNSOUND_WORKFLOW_NET,
             :powl,
             "Reachable livelock detected: inescapable cycle from marking #{inspect(first_livelock)} cannot reach sink",
             %{livelock_marking: first_livelock, cycle_markings: unreachable_list}
           )}
        end

      true ->
        :ok
    end
  end

  defp compute_backward_reachability(visited, graph, target_end_marking) do
    # Invert graph: child_marking => [parent_marking]
    inverted_graph =
      Enum.reduce(graph, %{}, fn {parent, successors}, acc ->
        Enum.reduce(successors, acc, fn {_t, child}, inner_acc ->
          Map.update(inner_acc, child, MapSet.new([parent]), &MapSet.put(&1, parent))
        end)
      end)

    # Backward BFS from target_end_marking
    if MapSet.member?(visited, target_end_marking) do
      traverse_backward_markings([target_end_marking], inverted_graph, MapSet.new([target_end_marking]))
    else
      MapSet.new()
    end
  end

  defp traverse_backward_markings([], _inverted, reached), do: reached

  defp traverse_backward_markings([curr | rest], inverted, reached) do
    parents = Map.get(inverted, curr, MapSet.new()) |> MapSet.to_list()
    new_parents = Enum.reject(parents, &MapSet.member?(reached, &1))
    new_reached = Enum.reduce(new_parents, reached, &MapSet.put(&2, &1))

    traverse_backward_markings(rest ++ new_parents, inverted, new_reached)
  end

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

  @doc "Checks if node u can reach node v in the structural flow"
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
