# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architecture

Full architecture, DSL, semantic-correspondence table, refusal vocabulary, and Ash.Reactor
integration law live in **`AGENTS.md`** — read it first. Summary: AshR2RML is not an
`Ash.DataLayer`; it compiles Ash resource metadata + semantic annotations into a normalized
mapping IR (`AshR2RML.Mapping.*`), then renders that IR to standards-valid W3C R2RML Turtle and
native `Ash.Type` representations. `AshPostgres` (or other data layers) still owns persistence;
Ontop owns SPARQL-to-SQL OBDA rewriting. **Normalize to IR first, verify second, render third** —
never generate R2RML Turtle directly from ad-hoc resource introspection.

Two convergent workflows produce the same IR: Ash-first (DSL annotations on an `Ash.Resource`)
and ontology-first (RDF/OWL/SHACL → `AshR2RML.SemanticTypes` DfCM compiler → generated
`Ash.Type`/`Ash.Resource`).

## Commands

```bash
# Setup
mix deps.get

# Format
mix format --check-formatted        # verify
mix format                          # fix

# Compile (warnings are errors in CI)
mix compile --warnings-as-errors

# Static analysis
mix credo --strict
mix sobelow --skip
mix dialyzer

# Spark DSL tooling (after changing the r2rml/rdf DSL extension)
mix spark.formatter --extensions AshR2RML.Resource
mix spark.cheat_sheets --extensions AshR2RML.Resource

# Tests — ascending verification ladder (see AGENTS.md for full rationale)
mix test test/unit/                                    # pure unit / mapping IR
mix test test/adversarial/ test/negative/               # adversarial closure & refusal suites
mix test test/fortune5/                                 # enterprise / ODRL policy suites
mix test test/adversarial/ontop_postgres_test.exs        # live Ontop OBDA SPARQL (needs Ontop+Postgres)
mix test test/adversarial/reactor_saga_test.exs          # Reactor saga rollback/compensation

# Single test file / single test
mix test test/semantic_types_test.exs
mix test test/semantic_types_test.exs:42

# Coverage (threshold 70%, configured via ExCoveralls)
mix coveralls
mix coveralls.github

# Docs
mix docs

# Package build / release sanity
mix hex.build
```

Elixir `~> 1.17` required. `mix.exs` compiles `test/support` into `lib`/`test` paths only for
`Mix.env() == :test`.

## Working in this repo

- Public DSL surface: `r2rml do ... end` and per-attribute/relationship `rdf do predicate ... end`
  blocks, via the `AshR2RML` Spark extension on `use Ash.Resource, extensions: [AshR2RML]`.
- Runtime mapping/compile APIs return `{:error, %AshR2RML.Refusal{}}` with one of the typed
  `REFUSED_*` reasons listed in AGENTS.md — never a bare exception or silent fallback (e.g. no
  "unknown Ash type → string" coercion for datatypes).
- Custom RDF-aware Ash types implement the `AshR2RML.Type` behaviour
  (`semantic_kind/0`, `datatype_iri/0`, `to_rdf/1`, `from_rdf/1`).
- Reactor steps live under `AshR2RML.Reactor.Steps.*` with 3-arity `run/3`/`compensate/4`/`undo/3`;
  compensation on failure runs in strict reverse LIFO order. Lifecycle telemetry is emitted as
  IEEE OCEL 2.0 events via `AshR2RML.Reactor.Middleware.TelemetryLogger`.
- `usage-rules/*.md` are the per-topic reference docs (r2rml, obda, ontology-first, semantic-ir,
  datatypes, vectors, spatial, actions, dsl, testing, etc.) — check the matching file before
  implementing in that area rather than re-deriving conventions from scratch.
