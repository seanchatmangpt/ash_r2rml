# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Reactor.Pipeline do
  @moduledoc """
  Full end-to-end Zach Daniel–style `Reactor` pipeline exercising every public
  facet of AshR2RML through 6 named, module-backed steps:

  1. **compile_resources** — compile Ash resource modules into a normalized
     `AshR2RML.Mapping.Bundle` (`AshR2RML.Reactor.Steps.CompileResources`).
  2a. **verify_alignment** — fail-closed schema alignment verification
      (`AshR2RML.Reactor.Steps.VerifyAlignment`), runs concurrently with 2b.
  2b. **evaluate_differential** — optional SPARQL behavioral parity evaluation
      (`AshR2RML.Reactor.Steps.EvaluateDifferential`), runs concurrently with 2a.
  3. **attach_provenance** — attach W3C PROV-O `prov:generatedAtTime` and
     `prov:wasDerivedFrom` predicate-object maps after alignment clears
     (`AshR2RML.Reactor.Steps.AttachProvenance`).
  4. **apply_policy** — actor-scoped Ash policy filtering (nil-safe)
     (`AshR2RML.Reactor.Steps.ApplyPolicy`).
  5. **render_r2rml_turtle** — render final W3C R2RML Turtle string
     (`AshR2RML.Reactor.Steps.RenderTurtle`).

  Returns the final W3C R2RML Turtle string.

  ## Inputs

  - `:resources`    — a single Ash resource module or a list of modules.
  - `:actor`        — optional actor map for policy-based projection filtering.
  - `:observations` — optional list of `%AshR2RML.SPARQL.Observation{}` structs
                      (>= 2 required for the differential step to be active).
  - `:metadata`     — optional map forwarded to the differential evaluator.

  ## Example

      Reactor.run(AshR2RML.Reactor.Pipeline, %{
        resources: [MyApp.User, MyApp.Org],
        actor: %{id: "alice", role: :admin},
        observations: [],
        metadata: %{}
      })
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

  ##
  ## Step 1 — Compile resource modules → %AshR2RML.Mapping.Bundle{}
  ##
  step :compile_resources, AshR2RML.Reactor.Steps.CompileResources do
    argument :resources, input(:resources)
    max_retries 1
  end

  ##
  ## Step 2a — Fail-closed schema alignment verification (concurrent with 2b)
  ##
  step :verify_alignment, AshR2RML.Reactor.Steps.VerifyAlignment do
    argument :bundle, result(:compile_resources)
  end

  ##
  ## Step 2b — Optional SPARQL differential evaluation (concurrent with 2a)
  ##
  step :evaluate_differential, AshR2RML.Reactor.Steps.EvaluateDifferential do
    argument :observations, input(:observations)
    argument :metadata, input(:metadata)
    max_retries 0
  end

  ##
  ## Step 3 — Attach W3C PROV-O provenance maps (waits for alignment to clear)
  ##
  step :attach_provenance, AshR2RML.Reactor.Steps.AttachProvenance do
    argument :bundle, result(:compile_resources)
    wait_for :verify_alignment
  end

  ##
  ## Step 4 — Actor-scoped policy filter (nil actor is a no-op in the step module)
  ##
  step :apply_policy, AshR2RML.Reactor.Steps.ApplyPolicy do
    argument :bundle, result(:attach_provenance)
    argument :actor, input(:actor)
  end

  ##
  ## Step 5 — Render final W3C R2RML Turtle string
  ##
  step :render_r2rml_turtle, AshR2RML.Reactor.Steps.RenderTurtle do
    argument :bundle, result(:apply_policy)
  end

  return :render_r2rml_turtle
end
