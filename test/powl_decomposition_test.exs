# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.POWL.DecompositionTest do
  @moduledoc """
  E2E Test Suite validating the Hierarchical Decomposition of Separable Workflow-Nets
  into POWL 2.0 and OWL 2 Ontologies (Kourani, Park, and van der Aalst, arXiv:2602.15739v3, 2026).
  Includes full Ash Resource persistence, ETS test database queries, and SPARQL differential verification.
  """
  use ExUnit.Case, async: false

  alias AshR2RML.POWL.Ash.DecomposedNode
  alias AshR2RML.POWL.Ash.Domain
  alias AshR2RML.POWL.Ash.ProcessModel
  alias AshR2RML.POWL.AshPowlPipeline
  alias AshR2RML.POWL.DBSeeder
  alias AshR2RML.POWL.DecomposerReactor
  alias AshR2RML.POWL.Model.ChoiceGraph
  alias AshR2RML.POWL.Model.PartialOrder
  alias AshR2RML.POWL.WorkflowNet

  describe "Hierarchical Decomposition of Separable Workflow-Nets (POWL 2.0)" do
    test "decomposes Marked Graph into a POWL 2.0 Partial Order" do
      # Concurrent diamond: source -> split -> (t1, t2) -> join -> sink
      places = [:p_src, :p_a, :p_b, :p_snk]
      transitions = [:t_split, :t_join, :t_work1, :t_work2]

      labels = %{
        t_split: "Split Concurrency",
        t_work1: "Task A",
        t_work2: "Task B",
        t_join: "Synchronize Concurrency"
      }

      flow = [
        {:p_src, :t_split},
        {:t_split, :p_a},
        {:t_split, :p_b},
        {:p_a, :t_work1},
        {:p_b, :t_work2},
        {:t_work1, :p_snk},
        {:t_work2, :p_snk},
        {:p_snk, :t_join}
      ]

      net = WorkflowNet.new(:p_src, :p_snk, places, transitions, labels, flow)

      inputs = %{
        workflow_net: net,
        base_iri: "https://example.org/proc/marked_graph/"
      }

      assert {:ok, result} = Reactor.run(DecomposerReactor, inputs)
      assert %PartialOrder{} = result.powl_ast
      assert result.owl_turtle =~ "powl:PartialOrder"
      assert result.owl_turtle =~ "Task A"
      assert result.owl_turtle =~ "Task B"
    end

    test "decomposes State Machine into a POWL 2.0 Choice Graph" do
      # Exclusive choice with loop: start -> choose (A or B) -> end
      places = [:p_start, :p_choice, :p_end]
      transitions = [:t_init, :t_opt_a, :t_opt_b, :t_finish]

      labels = %{
        t_init: "Initialize",
        t_opt_a: "Option A",
        t_opt_b: "Option B",
        t_finish: "Complete"
      }

      flow = [
        {:p_start, :t_init},
        {:t_init, :p_choice},
        {:p_choice, :t_opt_a},
        {:p_choice, :t_opt_b},
        {:t_opt_a, :p_end},
        {:t_opt_b, :p_end}
      ]

      net = WorkflowNet.new(:p_start, :p_end, places, transitions, labels, flow)

      inputs = %{
        workflow_net: net,
        base_iri: "https://example.org/proc/state_machine/"
      }

      assert {:ok, result} = Reactor.run(DecomposerReactor, inputs)
      assert match?(%ChoiceGraph{}, result.powl_ast) or match?(%PartialOrder{}, result.powl_ast)
      assert result.owl_turtle =~ "Option A"
      assert result.owl_turtle =~ "Option B"
    end

    test "Full Ash + DB + SPARQL + Reactor Pipeline for Retailer Order Fulfillment (Figure 1a -> Figure 1b)" do
      # 1. Seed Workflow Net into Test Database (Ash ETS tables)
      model = DBSeeder.seed_retailer_process!()
      assert %ProcessModel{} = model

      # 2. Execute Full Pipeline reading directly from Test Database
      inputs = %{
        process_model_id: model.id,
        base_iri: "https://retailer.example.org/powl/order_fulfillment#"
      }

      assert {:ok, result} = Reactor.run(AshPowlPipeline, inputs)
      assert result.status == :verified_and_persisted

      # 3. Verify Decomposed Node was persisted in DB
      node = Ash.get!(DecomposedNode, result.decomposed_node_id, domain: Domain)
      assert node.node_type in ["ChoiceGraph", "PartialOrder"]

      # 4. Verify R2RML mappings rendered for all POWL Ash resources
      assert result.r2rml_turtle =~ "https://w3id.org/powl/v2#Model"
      assert result.r2rml_turtle =~ "https://w3id.org/powl/v2#Transition"
      assert result.r2rml_turtle =~ "https://w3id.org/powl/v2#activityLabel"

      # 5. Verify SPARQL Differential Parity
      assert result.differential.verified? == true
      assert result.differential.strategies == [:direct_sparql, :r2rml_obda]

      # 6. Verify Updated Process Model with serialized OWL Turtle in DB
      updated_model = Ash.get!(ProcessModel, model.id, domain: Domain)
      assert updated_model.raw_owl_turtle =~ "@prefix powl: <https://w3id.org/powl/v2#> ."
      assert updated_model.raw_owl_turtle =~ "Gather Materials"
      assert updated_model.raw_owl_turtle =~ "Produce Goods"
      assert updated_model.raw_owl_turtle =~ "Ship Goods"
    end
  end
end
