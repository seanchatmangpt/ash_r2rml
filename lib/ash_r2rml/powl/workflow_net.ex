# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.POWL.WorkflowNet do
  @moduledoc """
  Production workflow-net model, decomposition, and bounded soundness verifier.

  Reachability uses ordinary Petri-net token multiplicities. The verifier never
  collapses a marking to a set, never treats "sink is marked" as proper
  completion, and never upgrades an exhausted state-space bound to proof.
  """

  alias AshR2RML.Refusal

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
  @type marking :: %{optional(place()) => non_neg_integer()}
  @type t :: %__MODULE__{
          source: place(),
          sink: place(),
          places: MapSet.t(place()),
          transitions: MapSet.t(transition()),
          labels: map(),
          preset: map(),
          postset: map()
        }

  @default_max_states 50_000
  @default_place_bound 1

  @spec new(place(), place(), [place()], [transition()], map(), [{term(), term()}]) :: t()
  def new(source, sink, places, transitions, labels, flow) do
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
      places: MapSet.new([source, sink | places]),
      transitions: MapSet.new(transitions),
      labels: labels,
      preset: preset,
      postset: postset
    }
  end

  def preset(%__MODULE__{preset: preset}, node), do: Map.get(preset, node, MapSet.new())
  def postset(%__MODULE__{postset: postset}, node), do: Map.get(postset, node, MapSet.new())

  @spec verify_structure(t()) :: :ok | {:error, Refusal.t()}
  def verify_structure(%__MODULE__{} = net) do
    sources = Enum.filter(net.places, &(MapSet.size(preset(net, &1)) == 0))
    sinks = Enum.filter(net.places, &(MapSet.size(postset(net, &1)) == 0))
    invalid = invalid_arcs(net)

    cond do
      not MapSet.disjoint?(net.places, net.transitions) ->
        invalid_structure("places and transitions must be disjoint", %{
          overlap: MapSet.intersection(net.places, net.transitions) |> MapSet.to_list()
        })

      not MapSet.member?(net.places, net.source) ->
        invalid_structure("declared source is not a place", %{source: net.source})

      not MapSet.member?(net.places, net.sink) ->
        invalid_structure("declared sink is not a place", %{sink: net.sink})

      invalid != [] ->
        invalid_structure("flow must be bipartite and reference declared nodes", %{invalid_arcs: invalid})

      MapSet.new(sources) != MapSet.new([net.source]) ->
        invalid_structure("declared source must be the unique source place", %{source: net.source, observed: sources})

      MapSet.new(sinks) != MapSet.new([net.sink]) ->
        invalid_structure("declared sink must be the unique sink place", %{sink: net.sink, observed: sinks})

      not all_nodes_connected?(net) ->
        invalid_structure("every node must lie on a path from source to sink", %{})

      true ->
        :ok
    end
  end

  @spec verify_soundness(t(), keyword()) :: :ok | {:error, Refusal.t()} | {:unknown, map()}
  def verify_soundness(%__MODULE__{} = net, opts \\ []) do
    case soundness_report(net, opts) do
      {:ok, _} -> :ok
      other -> other
    end
  end

  @spec soundness_report(t(), keyword()) :: {:ok, map()} | {:error, Refusal.t()} | {:unknown, map()}
  def soundness_report(%__MODULE__{} = net, opts \\ []) do
    max_states = Keyword.get(opts, :max_states, @default_max_states)
    place_bound = Keyword.get(opts, :place_bound, @default_place_bound)

    with :ok <- verify_structure(net),
         :ok <- validate_bounds(max_states, place_bound),
         {:ok, graph} <- explore_state_space(net, max_states, place_bound) do
      evaluate_soundness(net, graph, max_states, place_bound)
    else
      {:unsafe, transition, marking} ->
        {:error,
         Refusal.new(
           :REFUSED_UNSAFE_WORKFLOW_NET,
           :powl,
           "reachable firing exceeds the admitted place bound",
           %{transition: transition, marking: marking, place_bound: place_bound}
         )}

      {:unknown, _} = unknown -> unknown
      {:error, _} = error -> error
    end
  end

  defp validate_bounds(max_states, place_bound)
       when is_integer(max_states) and max_states > 0 and is_integer(place_bound) and place_bound > 0,
       do: :ok

  defp validate_bounds(max_states, place_bound),
    do: invalid_structure("soundness bounds must be positive integers", %{max_states: max_states, place_bound: place_bound})

  defp explore_state_space(net, max_states, place_bound) do
    initial = %{net.source => 1}
    key = marking_key(initial)

    do_explore(
      net,
      :queue.in(initial, :queue.new()),
      %{key => initial},
      %{},
      MapSet.new(),
      max_states,
      place_bound
    )
  end

  defp do_explore(net, queue, markings, edges, fired, max_states, place_bound) do
    case :queue.out(queue) do
      {:empty, _} ->
        {:ok, %{markings: markings, edges: edges, fired: fired}}

      {{:value, marking}, rest_queue} ->
        from_key = marking_key(marking)
        enabled = Enum.filter(net.transitions, &transition_enabled?(net, &1, marking))

        Enum.reduce_while(enabled, {:ok, rest_queue, markings, edges, fired}, fn transition,
                                                                                {:ok, q, ms, es, fs} ->
          next = fire_transition(net, transition, marking)

          cond do
            exceeds_place_bound?(next, place_bound) ->
              {:halt, {:unsafe, transition, next}}

            true ->
              next_key = marking_key(next)
              es = Map.update(es, from_key, MapSet.new([next_key]), &MapSet.put(&1, next_key))
              fs = MapSet.put(fs, transition)

              cond do
                Map.has_key?(ms, next_key) ->
                  {:cont, {:ok, q, ms, es, fs}}

                map_size(ms) >= max_states ->
                  {:halt,
                   {:unknown,
                    %{
                      status: :UNKNOWN,
                      standing: :bounded_state_space_exhausted,
                      reason: :state_space_bound_exceeded,
                      max_states: max_states,
                      place_bound: place_bound,
                      observed_states: map_size(ms),
                      frontier_marking: next
                    }}}

                true ->
                  {:cont, {:ok, :queue.in(next, q), Map.put(ms, next_key, next), es, fs}}
              end
          end
        end)
        |> case do
          {:ok, q, ms, es, fs} -> do_explore(net, q, ms, es, fs, max_states, place_bound)
          other -> other
        end
    end
  end

  defp evaluate_soundness(net, graph, max_states, place_bound) do
    final = %{net.sink => 1}
    final_key = marking_key(final)
    all_keys = graph.markings |> Map.keys() |> MapSet.new()
    dead = MapSet.difference(net.transitions, graph.fired)

    improper =
      graph.markings
      |> Map.values()
      |> Enum.filter(&(Map.get(&1, net.sink, 0) > 0 and &1 != final))

    completable = reverse_reachable(graph.edges, final_key)
    non_completing = MapSet.difference(all_keys, completable)

    cond do
      not Map.has_key?(graph.markings, final_key) ->
        unsound("final marking is unreachable", %{final_marking: final})

      MapSet.size(dead) > 0 ->
        unsound("dead transitions detected", %{dead: dead |> MapSet.to_list() |> Enum.sort_by(&inspect/1)})

      improper != [] ->
        unsound("proper completion violated", %{witness: hd(improper), final_marking: final})

      MapSet.size(non_completing) > 0 ->
        witness_key = Enum.at(non_completing, 0)
        unsound("option to complete violated", %{witness: Map.fetch!(graph.markings, witness_key)})

      true ->
        {:ok,
         %{
           status: :ALIVE,
           standing: :bounded_sound_workflow_net,
           reachable_markings: map_size(graph.markings),
           fired_transitions: graph.fired |> MapSet.to_list() |> Enum.sort_by(&inspect/1),
           final_marking: final,
           max_states: max_states,
           place_bound: place_bound,
           proof_scope: :exhaustive_within_admitted_bounds
         }}
    end
  end

  defp transition_enabled?(net, transition, marking),
    do: Enum.all?(preset(net, transition), &(Map.get(marking, &1, 0) >= 1))

  defp fire_transition(net, transition, marking) do
    marking = Enum.reduce(preset(net, transition), marking, &adjust_token(&2, &1, -1))
    marking = Enum.reduce(postset(net, transition), marking, &adjust_token(&2, &1, 1))
    normalize_marking(marking)
  end

  defp adjust_token(marking, place, delta), do: Map.update(marking, place, delta, &(&1 + delta))
  defp normalize_marking(marking), do: marking |> Enum.reject(fn {_p, count} -> count == 0 end) |> Map.new()
  defp exceeds_place_bound?(marking, bound), do: Enum.any?(marking, fn {_p, count} -> count > bound end)

  defp marking_key(marking) do
    marking |> Enum.sort_by(fn {place, _} -> inspect(place) end) |> List.to_tuple()
  end

  defp reverse_reachable(edges, final_key) do
    reverse =
      Enum.reduce(edges, %{}, fn {from, tos}, acc ->
        Enum.reduce(tos, acc, fn to, inner -> Map.update(inner, to, MapSet.new([from]), &MapSet.put(&1, from)) end)
      end)

    do_reverse_reachable([final_key], reverse, MapSet.new([final_key]))
  end

  defp do_reverse_reachable([], _reverse, visited), do: visited

  defp do_reverse_reachable([key | rest], reverse, visited) do
    previous = Map.get(reverse, key, MapSet.new()) |> Enum.reject(&MapSet.member?(visited, &1))
    visited = Enum.reduce(previous, visited, &MapSet.put(&2, &1))
    do_reverse_reachable(rest ++ previous, reverse, visited)
  end

  defp invalid_structure(detail, evidence),
    do: {:error, Refusal.new(:REFUSED_INVALID_WORKFLOW_NET, :powl, detail, evidence)}

  defp unsound(detail, evidence),
    do: {:error, Refusal.new(:REFUSED_UNSOUND_WORKFLOW_NET, :powl, detail, evidence)}

  defp flow_arcs(net),
    do:
      net.postset
      |> Enum.flat_map(fn {from, targets} -> Enum.map(targets, &{from, &1}) end)
      |> Enum.sort_by(fn {from, to} -> {inspect(from), inspect(to)} end)

  defp invalid_arcs(net) do
    known = MapSet.union(net.places, net.transitions)

    Enum.reject(flow_arcs(net), fn {from, to} ->
      MapSet.member?(known, from) and MapSet.member?(known, to) and
        ((MapSet.member?(net.places, from) and MapSet.member?(net.transitions, to)) or
           (MapSet.member?(net.transitions, from) and MapSet.member?(net.places, to)))
    end)
  end

  defp all_nodes_connected?(net) do
    net.places
    |> MapSet.union(net.transitions)
    |> Enum.all?(fn node ->
      (node == net.source or reachable?(net, net.source, node)) and
        (node == net.sink or reachable?(net, node, net.sink))
    end)
  end

  def state_machine?(net),
    do: Enum.all?(net.transitions, &(MapSet.size(preset(net, &1)) <= 1 and MapSet.size(postset(net, &1)) <= 1))

  def marked_graph?(net),
    do: Enum.all?(net.places, &(MapSet.size(preset(net, &1)) <= 1 and MapSet.size(postset(net, &1)) <= 1))

  def forward_restricted_reachability(net, place, stop),
    do: traverse(net, [place], stop, :forward, MapSet.new(), MapSet.new())

  def backward_restricted_reachability(net, place, stop),
    do: traverse(net, [place], stop, :backward, MapSet.new(), MapSet.new())

  defp traverse(_net, [], _stop, _direction, _visited, acc), do: acc

  defp traverse(net, [current | rest], stop, direction, visited, acc) do
    if MapSet.member?(visited, current) or current == stop do
      traverse(net, rest, stop, direction, visited, acc)
    else
      visited = MapSet.put(visited, current)
      next = if direction == :forward, do: postset(net, current), else: preset(net, current)
      acc = if MapSet.member?(net.transitions, current), do: MapSet.put(acc, current), else: acc
      traverse(net, rest ++ MapSet.to_list(next), stop, direction, visited, acc)
    end
  end

  def reachable?(net, from, to), do: do_reachable(net, [from], to, MapSet.new())
  defp do_reachable(_net, [], _target, _visited), do: false

  defp do_reachable(net, [current | rest], target, visited) do
    cond do
      current == target and MapSet.size(visited) > 0 -> true
      MapSet.member?(visited, current) -> do_reachable(net, rest, target, visited)
      true ->
        visited = MapSet.put(visited, current)
        next = postset(net, current) |> MapSet.to_list()
        if target in next, do: true, else: do_reachable(net, rest ++ next, target, visited)
    end
  end

  def partition_mg(net) do
    initial = Enum.map(net.transitions, &MapSet.new([&1]))

    after_splits =
      Enum.reduce(net.places, initial, fn place, parts ->
        targets = postset(net, place) |> MapSet.to_list()

        if length(targets) > 1 do
          group =
            Enum.filter(net.transitions, fn t ->
              Enum.any?(targets, fn a ->
                Enum.any?(targets, fn b -> a != b and reachable?(net, a, t) and not reachable?(net, b, t) end)
              end)
            end)
            |> MapSet.new()

          merge_overlapping_parts(parts, group)
        else
          parts
        end
      end)

    Enum.reduce(net.places, after_splits, fn place, parts ->
      sources = preset(net, place) |> MapSet.to_list()

      if length(sources) > 1 do
        group =
          Enum.filter(net.transitions, fn t ->
            Enum.any?(sources, fn a ->
              Enum.any?(sources, fn b -> a != b and reachable?(net, t, a) and not reachable?(net, t, b) end)
            end)
          end)
          |> MapSet.new()

        merge_overlapping_parts(parts, group)
      else
        parts
      end
    end)
  end

  def partition_sm(net) do
    initial = Enum.map(net.transitions, &MapSet.new([&1]))

    after_splits =
      Enum.reduce(net.transitions, initial, fn split, parts ->
        branches = postset(net, split) |> MapSet.to_list()

        if length(branches) > 1 do
          threads =
            Enum.filter(net.transitions, fn t ->
              Enum.any?(branches, fn a ->
                Enum.any?(branches, fn b ->
                  a != b and MapSet.member?(forward_restricted_reachability(net, a, split), t) and
                    not MapSet.member?(forward_restricted_reachability(net, b, split), t)
                end)
              end)
            end)

          merge_overlapping_parts(parts, MapSet.new([split | threads]))
        else
          parts
        end
      end)

    Enum.reduce(net.transitions, after_splits, fn join, parts ->
      branches = preset(net, join) |> MapSet.to_list()

      if length(branches) > 1 do
        threads =
          Enum.filter(net.transitions, fn t ->
            Enum.any?(branches, fn a ->
              Enum.any?(branches, fn b ->
                a != b and MapSet.member?(backward_restricted_reachability(net, a, join), t) and
                  not MapSet.member?(backward_restricted_reachability(net, b, join), t)
              end)
            end)
          end)

        merge_overlapping_parts(parts, MapSet.new([join | threads]))
      else
        parts
      end
    end)
  end

  defp merge_overlapping_parts(parts, group) do
    if MapSet.size(group) <= 1 do
      parts
    else
      {overlap, rest} = Enum.split_with(parts, &(not MapSet.disjoint?(&1, group)))
      [Enum.reduce(overlap, group, &MapSet.union/2) | rest]
    end
  end

  def execution_order(net, parts) do
    indexed = Enum.with_index(parts)

    for {left, i} <- indexed,
        {right, j} <- indexed,
        i != j,
        dependency_exists?(net, left, right),
        into: MapSet.new(),
        do: {i, j}
  end

  def execution_flow(net, parts) do
    indexed = Enum.with_index(parts)

    internal =
      for {left, i} <- indexed,
          {right, j} <- indexed,
          i != j,
          dependency_exists?(net, left, right),
          do: {i, j}

    starts =
      for {part, i} <- indexed,
          Enum.any?(part, &MapSet.member?(preset(net, &1), net.source)),
          do: {:start, i}

    ends =
      for {part, i} <- indexed,
          Enum.any?(part, &MapSet.member?(postset(net, &1), net.sink)),
          do: {i, :end}

    MapSet.new(internal ++ starts ++ ends)
  end

  defp dependency_exists?(net, left, right) do
    exits = Enum.flat_map(left, &postset(net, &1)) |> MapSet.new()
    entries = Enum.flat_map(right, &preset(net, &1)) |> MapSet.new()
    not MapSet.disjoint?(exits, entries)
  end
end
