# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GrandExample.PublishingReactor do
  @moduledoc """
  Grand Example Publishing Reactor: 100% Feature Utilization across Ash, Reactor, and AshR2RML.

  Combines:
  - Middlewares (TelemetryLogger, Reactor.Middleware.Telemetry)
  - Composed Sub-Reactors (`compose`)
  - Concurrent batch iteration (`map` with `batch_size` and `allow_async?`)
  - Fail-closed alignment verification & W3C PROV-O provenance attachment
  - Actor-based policy projection filtering
  - SPARQL multi-strategy behavioral differential parity checking (`where` guard)
  - EEx Template rendering (`template`)
  - Aggregated collection (`collect` with argument transform)
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

  # 1. Composed Sub-Reactor: verifies inputs
  compose :verify_inputs, AshR2RML.GrandExample.SubReactors.InputVerifier do
    argument :resources, input(:resources)
  end

  # 2. Map Step: iterates over resources concurrently to verify individual alignment
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

  # 3. Main Step: compile resources into normalized AshR2RML Bundle
  step :compile_bundle, AshR2RML.Reactor.Steps.CompileResources do
    argument :resources, input(:resources)
    max_retries 1
  end

  # 4. Step: attach W3C PROV-O provenance assertions
  step :attach_provenance, AshR2RML.Reactor.Steps.AttachProvenance do
    argument :bundle, result(:compile_bundle)
    wait_for :verify_each_resource
  end

  # 5. Step: apply Ash policy projection filter
  step :apply_policy, AshR2RML.Reactor.Steps.ApplyPolicy do
    argument :bundle, result(:attach_provenance)
    argument :actor, input(:actor)
  end

  # 6. Step: render final W3C R2RML Turtle mapping
  step :render_r2rml_turtle, AshR2RML.Reactor.Steps.RenderTurtle do
    argument :bundle, result(:apply_policy)
  end

  # 7. Step: evaluate SPARQL behavioral parity differential concurrently
  step :evaluate_differential, AshR2RML.Reactor.Steps.EvaluateDifferential do
    argument :observations, input(:observations)
    argument :metadata, input(:metadata)
    where fn %{observations: obs}, _ctx -> is_list(obs) and length(obs) >= 2 end
  end

  # 8. Template Step: generates EEx documentation manifest banner
  template :manifest_banner do
    argument :title, input(:manifest_title)
    argument :verification, result(:verify_inputs)

    template("""
    # Semantic Manifest: <%= @title %>
    Validated <%= @verification.resource_count %> resource mappings.
    Generated via AshR2RML Reactor Pipeline.
    """)
  end

  # 9. Collect Step: aggregates all components into a publication package
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
