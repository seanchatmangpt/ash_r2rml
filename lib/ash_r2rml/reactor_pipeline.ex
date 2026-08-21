# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Reactor.Pipeline do
  @moduledoc """
  End-to-end Reactor pipeline over AshR2RML's existing public surfaces.

  The pipeline compiles Ash resources, verifies alignment, optionally evaluates
  observed SPARQL differentials, applies only explicitly supplied PROV-O
  projections, applies actor-scoped policy filtering, and renders R2RML.

  `:metadata` is evidence/configuration carried by the orchestration layer. Two
  optional keys have semantic effect:

  - `:subject` scopes a differential receipt to a caller-provided subject.
  - `:provenance` explicitly selects PROV-O projections, for example
    `%{generated_at: :updated_at, derived_from: "https://example.org/source/{id}"}`.

  No provenance mapping is invented when `:provenance` is absent.
  """

  use Reactor

  middlewares do
    middleware(AshR2RML.Reactor.Middleware.TelemetryLogger)
    middleware(Reactor.Middleware.Telemetry)
  end

  input(:resources)
  input(:actor)
  input(:observations)
  input(:metadata)

  step :compile_resources, AshR2RML.Reactor.Steps.CompileResources do
    argument :resources, input(:resources)
    max_retries 1
  end

  step :verify_alignment, AshR2RML.Reactor.Steps.VerifyAlignment do
    argument :bundle, result(:compile_resources)
  end

  step :evaluate_differential, AshR2RML.Reactor.Steps.EvaluateDifferential do
    argument :observations, input(:observations)
    argument :metadata, input(:metadata)
    max_retries 0
  end

  step :attach_provenance, AshR2RML.Reactor.Steps.AttachProvenance do
    argument :bundle, result(:compile_resources)
    argument :metadata, input(:metadata)
    wait_for :verify_alignment
  end

  step :apply_policy, AshR2RML.Reactor.Steps.ApplyPolicy do
    argument :bundle, result(:attach_provenance)
    argument :actor, input(:actor)
  end

  step :render_r2rml_turtle, AshR2RML.Reactor.Steps.RenderTurtle do
    argument :bundle, result(:apply_policy)
  end

  return :render_r2rml_turtle
end
