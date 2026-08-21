# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.POWL.DBSeeder do
  @moduledoc """
  Database Seeder and Hydration layer for persisting and querying Workflow Nets
  and POWL structures using Ash resources and ETS storage.
  """

  require Ash.Query

  alias AshR2RML.POWL.Ash.Domain
  alias AshR2RML.POWL.Ash.FlowArc
  alias AshR2RML.POWL.Ash.Place
  alias AshR2RML.POWL.Ash.ProcessModel
  alias AshR2RML.POWL.Ash.Transition
  alias AshR2RML.POWL.WorkflowNet

  @doc "Seeds the Retailer Order Fulfillment Process (Figure 1a from Kourani et al. 2026) into Ash ETS tables."
  def seed_retailer_process! do
    # 1. Create Process Model
    model =
      ProcessModel
      |> Ash.Changeset.for_create(
        :create,
        %{
          name: "Retailer Order Fulfillment Process (Kourani et al. 2026)",
          root_type: "ChoiceGraph"
        },
        domain: Domain
      )
      |> Ash.create!(domain: Domain)

    # 2. Create Places
    places_data = [
      {"p_in", true, false},
      {"p_instock", false, false},
      {"p_prod", false, false},
      {"p_mat", false, false},
      {"p_sched", false, false},
      {"p_out", false, true},
      {"p_ship", false, false},
      {"p_cancel", false, false}
    ]

    Enum.each(places_data, fn {name, is_src, is_snk} ->
      Place
      |> Ash.Changeset.for_create(
        :create,
        %{
          process_model_id: model.id,
          name: name,
          is_source?: is_src,
          is_sink?: is_snk
        },
        domain: Domain
      )
      |> Ash.create!(domain: Domain)
    end)

    # 3. Create Transitions
    transitions_data = [
      {"t_check_stock", "Check Stock", false},
      {"t_gather_materials", "Gather Materials", false},
      {"t_schedule_prod", "Schedule Production", false},
      {"t_produce", "Produce Goods", false},
      {"t_notify_cust", "Notify Customer", false},
      {"t_ship", "Ship Goods", false},
      {"t_cancel", "Cancel Order", false},
      {"t_loopback", "Retry / Loopback", false}
    ]

    Enum.each(transitions_data, fn {key, label, silent?} ->
      Transition
      |> Ash.Changeset.for_create(
        :create,
        %{
          process_model_id: model.id,
          key_name: key,
          label: label,
          silent?: silent?
        },
        domain: Domain
      )
      |> Ash.create!(domain: Domain)
    end)

    # 4. Create Flow Arcs
    flows = [
      {"p_in", "t_check_stock"},
      {"t_check_stock", "p_instock"},
      {"t_check_stock", "p_prod"},
      {"p_prod", "t_gather_materials"},
      {"p_prod", "t_schedule_prod"},
      {"t_gather_materials", "p_mat"},
      {"t_schedule_prod", "p_sched"},
      {"p_mat", "t_produce"},
      {"p_sched", "t_produce"},
      {"p_sched", "t_notify_cust"},
      {"t_produce", "p_out"},
      {"t_notify_cust", "p_out"},
      {"p_instock", "t_ship"},
      {"p_instock", "t_cancel"},
      {"t_cancel", "p_cancel"},
      {"p_cancel", "t_loopback"},
      {"t_loopback", "p_in"},
      {"t_ship", "p_out"}
    ]

    Enum.each(flows, fn {src, tgt} ->
      FlowArc
      |> Ash.Changeset.for_create(
        :create,
        %{
          process_model_id: model.id,
          source_name: src,
          target_name: tgt
        },
        domain: Domain
      )
      |> Ash.create!(domain: Domain)
    end)

    model
  end

  @doc "Hydrates a WorkflowNet struct by querying the test database via Ash."
  def hydrate_workflow_net!(%ProcessModel{id: model_id}) do
    places =
      Place
      |> Ash.Query.filter(process_model_id == ^model_id)
      |> Ash.read!(domain: Domain)

    transitions =
      Transition
      |> Ash.Query.filter(process_model_id == ^model_id)
      |> Ash.read!(domain: Domain)

    flows =
      FlowArc
      |> Ash.Query.filter(process_model_id == ^model_id)
      |> Ash.read!(domain: Domain)

    source_place = Enum.find(places, & &1.is_source?).name |> String.to_atom()
    sink_place = Enum.find(places, & &1.is_sink?).name |> String.to_atom()

    all_places = Enum.map(places, &String.to_atom(&1.name))
    all_transitions = Enum.map(transitions, &String.to_atom(&1.key_name))

    labels =
      Map.new(transitions, fn t ->
        {String.to_atom(t.key_name), t.label}
      end)

    flow_tuples =
      Enum.map(flows, fn f ->
        {String.to_atom(f.source_name), String.to_atom(f.target_name)}
      end)

    WorkflowNet.new(
      source_place,
      sink_place,
      all_places,
      all_transitions,
      labels,
      flow_tuples
    )
  end
end
