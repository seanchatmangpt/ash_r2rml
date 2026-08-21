# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GrandExample.PublishingReactor do
  @moduledoc """
  Grand Example Publishing Reactor exercising Ash, Reactor, and AshR2RML public surfaces.

  The example deliberately keeps semantic choices caller-owned. In particular,
  PROV-O projection is driven by `metadata.provenance`; the workflow does not
  manufacture application provenance conventions on its own.
  """

  use Reactor

  middlewares do
    middleware(AshR2RML.Reactor.Middleware.TelemetryLogger)
    middleware(Reactor.Middleware.Telemetry)
  end

  input(:resources)
  input(:manifest_title)
  input(:actor)
  input(:observations)
  input(:metadata)

  compose :verify_inputs, AshR2RML.GrandExample.SubReactors.InputVerifier do
    argument :resources, input(:resources)
  end

  map :verify_each_resource do
    source input(:resources)
    batch_size 2
    allow_async?(true)

    step :verify_single do
      argument :resource, element(:verify_each_resource)

      run fn %{resource: resource}, _ctx ->
        {:ok, %{resource: resource, verified?: true}}
      end
    end
  end

  step :compile_bundle, AshR2RML.Reactor.Steps.CompileResources do
    argument :resources, input(:resources)
    max_retries 1
  end

  step :attach_provenance, AshR2RML.Reactor.Steps.AttachProvenance do
    argument :bundle, result(:compile_bundle)
    argument :metadata, input(:metadata)
    wait_for :verify_each_resource
  end

  step :apply_policy, AshR2RML.Reactor.Steps.ApplyPolicy do
    argument :bundle, result(:attach_provenance)
    argument :actor, input(:actor)
  end

  step :render_r2rml_turtle, AshR2RML.Reactor.Steps.RenderTurtle do
    argument :bundle, result(:apply_policy)
  end

  step :evaluate_differential, AshR2RML.Reactor.Steps.EvaluateDifferential do
    argument :observations, input(:observations)
    argument :metadata, input(:metadata)
    where fn %{observations: obs}, _ctx -> is_list(obs) and length(obs) >= 2 end
  end

  template :manifest_banner do
    argument :title, input(:manifest_title)
    argument :verification, result(:verify_inputs)

    template("""
    # Semantic Manifest: <%= @title %>
    Validated <%= @verification.resource_count %> resource mappings.
    Generated via AshR2RML Reactor Pipeline.
    """)
  end

  collect :publication_package do
    argument :banner, result(:manifest_banner)
    argument :turtle, result(:render_r2rml_turtle)
    argument :differential, result(:evaluate_differential)
    argument :title, input(:manifest_title)

    transform fn inputs ->
      %{
        title: inputs.title,
        banner: inputs.banner,
        r2rml_turtle: inputs.turtle,
        differential_result: inputs.differential,
        status: :ready_for_publication
      }
    end
  end

  return :publication_package
end
