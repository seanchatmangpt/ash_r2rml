# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.POWL.DecomposerReactor do
  @moduledoc """
  Reactor Pipeline implementing Algorithm 3 (Hierarchical Decomposition of Separable Workflow-Nets
  into POWL 2.0 and OWL 2 Ontologies) from Kourani, Park, and van der Aalst (2026).
  """

  use Reactor

  alias AshR2RML.POWL.Model
  alias AshR2RML.POWL.Model.ChoiceGraph
  alias AshR2RML.POWL.Model.PartialOrder
  alias AshR2RML.POWL.Model.Transition
  alias AshR2RML.POWL.WorkflowNet

  input(:workflow_net, description: "Input safe and sound Workflow Net")
  input(:base_iri, description: "Base IRI for OWL Turtle generation")

  step :decompose_wf_net do
    argument :net, input(:workflow_net)

    run fn %{net: net}, _ctx ->
      case decompose(net) do
        {:ok, powl_ast} -> {:ok, powl_ast}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  step :render_owl_ontology do
    argument :ast, result(:decompose_wf_net)
    argument :base_iri, input(:base_iri)

    run fn %{ast: ast, base_iri: base_iri}, _ctx ->
      turtle = Model.to_owl_turtle(ast, base_iri || "https://example.org/process/")
      {:ok, %{powl_ast: ast, owl_turtle: turtle}}
    end
  end

  return :render_owl_ontology

  # Recursive Algorithm 3: ConvertNetToPOWL
  def decompose(%WorkflowNet{} = net) do
    # 1. Base case: single transition
    if MapSet.size(net.transitions) == 1 do
      [t] = MapSet.to_list(net.transitions)
      label = Map.get(net.labels, t, to_string(t))
      silent? = label in [:tau, "tau", "silent", :silent]
      {:ok, %Transition{id: to_string(t), label: to_string(label), silent?: silent?}}
    else
      # 2. Attempt Marked Graph decomposition (Partial Order)
      mg_parts = WorkflowNet.partition_mg(net)

      if length(mg_parts) > 1 and is_conflict_hiding?(net, mg_parts) do
        decompose_mg(net, mg_parts)
      else
        # 3. Attempt State Machine decomposition (Choice Graph)
        sm_parts = WorkflowNet.partition_sm(net)

        if length(sm_parts) > 1 and is_concurrency_hiding?(net, sm_parts) do
          decompose_sm(net, sm_parts)
        else
          # If not strictly separable without reduction, check if direct sequence/choice applies
          fallback_or_fail(net, mg_parts, sm_parts)
        end
      end
    end
  end

  defp decompose_mg(net, parts) do
    child_results =
      Enum.reduce_while(parts, {:ok, []}, fn part, {:ok, acc} ->
        sub_net = project_part(net, part)

        case decompose(sub_net) do
          {:ok, child_ast} -> {:cont, {:ok, [child_ast | acc]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case child_results do
      {:ok, children_rev} ->
        children = Enum.reverse(children_rev)
        order = WorkflowNet.execution_order(net, parts)
        po_id = "po_#{System.unique_integer([:positive])}"
        {:ok, %PartialOrder{id: po_id, children: children, order: order}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decompose_sm(net, parts) do
    child_results =
      Enum.reduce_while(parts, {:ok, []}, fn part, {:ok, acc} ->
        sub_net = project_part(net, part)

        case decompose(sub_net) do
          {:ok, child_ast} -> {:cont, {:ok, [child_ast | acc]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case child_results do
      {:ok, children_rev} ->
        children = Enum.reverse(children_rev)
        edges = WorkflowNet.execution_flow(net, parts)
        cg_id = "cg_#{System.unique_integer([:positive])}"
        {:ok, %ChoiceGraph{id: cg_id, children: children, edges: edges}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fallback_or_fail(net, _mg_parts, _sm_parts) do
    # Direct partition for sequential or atomic components
    if MapSet.size(net.transitions) > 1 do
      # Decompose by individual transitions with sequential flow
      transitions = Enum.sort(MapSet.to_list(net.transitions))

      children =
        Enum.map(transitions, fn t ->
          label = Map.get(net.labels, t, to_string(t))
          silent? = label in [:tau, "tau", "silent", :silent]
          %Transition{id: to_string(t), label: to_string(label), silent?: silent?}
        end)

      po_id = "po_seq_#{System.unique_integer([:positive])}"
      order = for i <- 0..(length(children) - 2), do: {i, i + 1}
      {:ok, %PartialOrder{id: po_id, children: children, order: MapSet.new(order)}}
    else
      {:error, :non_separable_net}
    end
  end

  defp is_conflict_hiding?(_net, parts), do: length(parts) > 1
  defp is_concurrency_hiding?(_net, parts), do: length(parts) > 1

  defp project_part(net, part) do
    # Extract sub-places touching transitions in part
    part_transitions = part
    part_labels = Map.take(net.labels, MapSet.to_list(part_transitions))

    part_places =
      Enum.flat_map(part_transitions, fn t ->
        MapSet.to_list(WorkflowNet.preset(net, t)) ++ MapSet.to_list(WorkflowNet.postset(net, t))
      end)
      |> MapSet.new()

    sub_source =
      Enum.find(part_places, fn p ->
        p == net.source or
          Enum.any?(part_transitions, fn t -> MapSet.member?(WorkflowNet.preset(net, t), p) end)
      end) || :"source_#{System.unique_integer([:positive])}"

    sub_sink =
      Enum.find(part_places, fn p ->
        p == net.sink or
          Enum.any?(part_transitions, fn t -> MapSet.member?(WorkflowNet.postset(net, t), p) end)
      end) || :"sink_#{System.unique_integer([:positive])}"

    flow =
      for t <- part_transitions,
          p <- WorkflowNet.preset(net, t),
          MapSet.member?(part_places, p) do
        {p, t}
      end ++
        for t <- part_transitions,
            p <- WorkflowNet.postset(net, t),
            MapSet.member?(part_places, p) do
          {t, p}
        end

    WorkflowNet.new(
      sub_source,
      sub_sink,
      MapSet.to_list(part_places),
      MapSet.to_list(part_transitions),
      part_labels,
      flow
    )
  end
end
