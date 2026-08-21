# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Reactor.Pipeline do
  @moduledoc """
  Full end-to-end `Reactor`-style pipeline exercising every public facet of AshR2RML
  in a declarative saga with 7 named steps:

  1. **Compile** — compile one or more Ash resource modules (or a map-based profile) via
     `AshR2RML.Compiler.compile/1` or `AshR2RML.Compiler.compile_resources/1` into a
     normalized `AshR2RML.Mapping.Bundle`.
  2. **Align** — fail-closed schema alignment verification over every resource in the
     mapping bundle (`AshR2RML.VerifyMapping.Alignment.verify/1`).
  3. **Provenance** — attach W3C PROV-O `prov:generatedAtTime` and `prov:wasDerivedFrom`
     predicate-object maps to every resource (`AshR2RML.Mapping.Provenance`).
  4. **Policy** — filter the bundle through actor/policy projections
     (`AshR2RML.Policy.filter_for_actor/3`).
  5. **Introspect** — derive relational table names and join columns for every resource
     via `AshR2RML.DataLayer.table_name/1`.
  6. **Render** — render the enriched, filtered bundle into final W3C R2RML Turtle via
     `AshR2RML.R2RML.render/1`.
  7. **Differential** — optionally evaluate SPARQL behavioral parity across two execution
     strategies (`AshR2RML.SPARQL.Differential.compare/3`).

  Returns the final W3C R2RML Turtle string.

  ## Inputs

  - `:profile` — a single Ash resource module, a list of modules, or a map-based semantic profile.
  - `:actor` — optional actor map used for Ash policy-based projection filtering.
  - `:observations` — optional list of `%AshR2RML.SPARQL.Observation{}` structs (>= 2 required for differential).
  - `:metadata` — optional map passed to the differential evaluator.
  """

  use Reactor

  input(:profile)
  input(:actor)
  input(:observations)
  input(:metadata)

  ##
  ## Step 1 — Compile profile/resources → %AshR2RML.Mapping.Bundle{}
  ##
  step :compile_bundle do
    argument :profile, input(:profile)

    run fn %{profile: profile}, _ctx ->
      result =
        cond do
          is_atom(profile) ->
            AshR2RML.Compiler.compile_resources(profile)

          is_list(profile) ->
            AshR2RML.Compiler.compile_resources(profile)

          is_map(profile) ->
            # Map profile → full Compilation struct; extract bundle
            case AshR2RML.Compiler.compile(profile) do
              {:ok, %AshR2RML.Compilation{mapping_bundle: bundle}} -> {:ok, bundle}
              {:ok, bundle} -> {:ok, bundle}
              error -> error
            end
        end

      case result do
        {:ok, bundle} -> {:ok, bundle}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  ##
  ## Step 2 — Fail-closed schema alignment verification
  ##
  step :verify_alignment do
    argument :bundle, result(:compile_bundle)

    run fn %{bundle: bundle}, _ctx ->
      resources = bundle.resources || []
      results = Enum.map(resources, &AshR2RML.VerifyMapping.Alignment.verify/1)

      case Enum.find(results, &match?({:error, _}, &1)) do
        {:error, refusal} -> {:error, refusal}
        nil -> {:ok, :alignment_verified}
      end
    end
  end

  ##
  ## Step 3 — Attach W3C PROV-O provenance predicate maps to every resource
  ##
  step :attach_provenance do
    argument :bundle, result(:compile_bundle)
    wait_for :verify_alignment

    run fn %{bundle: bundle}, _ctx ->
      updated_resources =
        Enum.map(bundle.resources || [], fn res ->
          res
          |> AshR2RML.Mapping.Provenance.attach_generated_at_time(:updated_at)
          |> AshR2RML.Mapping.Provenance.attach_was_derived_from("https://example.org/prov/source/{id}")
        end)

      {:ok, %{bundle | resources: updated_resources}}
    end
  end

  ##
  ## Step 4 — Filter bundle through actor / Ash policy projections
  ##
  step :apply_policy_filter do
    argument :bundle, result(:attach_provenance)
    argument :actor, input(:actor)

    run fn %{bundle: bundle, actor: actor}, _ctx ->
      if is_nil(actor) do
        {:ok, bundle}
      else
        {:ok, AshR2RML.Policy.filter_for_actor(bundle, actor, [])}
      end
    end
  end

  ##
  ## Step 5 — Relational DataLayer introspection (table names)
  ##
  step :introspect_data_layer do
    argument :bundle, result(:apply_policy_filter)

    run fn %{bundle: bundle}, _ctx ->
      table_index =
        Map.new(bundle.resources || [], fn res ->
          table = AshR2RML.DataLayer.table_name(res.ash_resource)
          {res.ash_resource, table}
        end)

      {:ok, %{bundle: bundle, table_index: table_index}}
    end
  end

  ##
  ## Step 6 — Render final W3C R2RML Turtle
  ##
  step :render_r2rml_turtle do
    argument :introspected, result(:introspect_data_layer)

    run fn %{introspected: %{bundle: bundle}}, _ctx ->
      AshR2RML.R2RML.render(bundle)
    end
  end

  ##
  ## Step 7 — SPARQL behavioral differential evaluation (optional)
  ##
  step :evaluate_differential do
    argument :observations, input(:observations)
    argument :metadata, input(:metadata)

    run fn %{observations: obs, metadata: meta}, _ctx ->
      if is_list(obs) and length(obs) >= 2 do
        AshR2RML.SPARQL.Differential.compare("PipelineSubject", obs, meta || %{})
      else
        {:ok, nil}
      end
    end
  end

  return :render_r2rml_turtle
end
