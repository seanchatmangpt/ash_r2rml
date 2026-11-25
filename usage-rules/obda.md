# OBDA and virtual RDF

`AshR2RML.OBDA.InMemory` is the only runtime OBDA backend. It is in-process, runs SPARQL over an `RDF.Graph` materialized from real Ash reads, and works with any Ash data layer. There is no SQL surface and no external process.

## Architecture

```text
SPARQL
   ↓
AshR2RML.OBDA.query/3   (Worker: timeout + heap bound, telemetry, digest)
   ↓
AshR2RML.OBDA.InMemory  (Ash.read/2: policies, tenancy, field redaction apply)
   ↓
RDF.Graph → AshR2RML.SPARQL.Local → AshR2RML.OBDA.Result
```

## Bounded envelope: `AshR2RML.OBDA.query/3`

```elixir
{:ok, %AshR2RML.OBDA.Result{bindings: rows, triples: triples, stats: stats, digest: digest}} =
  AshR2RML.OBDA.query(MyApp.Domain, "SELECT ?s WHERE { ?s ?p ?o }",
    actor: actor,
    tenant: tenant,
    max_rows: 1_000,
    max_triples: 50_000,
    timeout_ms: 2_000,
    max_heap_words: 10_000_000
  )
```

The first argument is an Ash domain, a list of resource modules carrying the AshR2RML extension, or a list of `{ash_resource, mapping}` specs.

`Result` fields:

- `bindings`: canonically sorted SELECT rows (or the single ASK row).
- `triples`: canonically sorted CONSTRUCT/DESCRIBE statements.
- `kind`: `:bindings | :boolean | :rdf`.
- `stats`: `%{rows_read, triples_emitted, duration_us, resources_pruned_by_policy}`.
- `digest`: lowercase hex SHA-256 over the rendered R2RML Turtle, the SPARQL text and the canonical rows.

Bounds:

| option | default | breach |
|---|---|---|
| `max_rows` | 10_000 (per resource read) | `REFUSED_RESULT_LIMIT_EXCEEDED` |
| `max_triples` | 100_000 | `REFUSED_TRIPLE_LIMIT_EXCEEDED` (`InMemory`) / `REFUSED_RESOURCE_BOUND` (`OBDA`) |
| `timeout_ms` | 5_000 | `REFUSED_QUERY_TIMEOUT` |
| `max_heap_words` (BEAM `max_heap_size`, kill on breach) | 50_000_000 | `REFUSED_MEMORY_LIMIT_EXCEEDED` |

Other refusal codes `OBDA.query/3` emits: `REFUSED_UNSUPPORTED_SPARQL_FEATURE`, `REFUSED_UNAUTHORIZED`, `REFUSED_MISSING_TENANT`, `REFUSED_SENSITIVE_ATTRIBUTE_MATERIALIZATION`, `REFUSED_READ_FAILED`, `REFUSED_WORKER_CRASHED`. Failures return `{:error, %AshR2RML.Error{}}` (or `%AshR2RML.Refusal{}`); `AshR2RML.Error.retryable?/1` is true only for read failure, timeout and worker crash. Telemetry: `[:ash_r2rml, :obda, :query, :start | :stop | :exception]`.

`pushdown: false` forces a full read instead of the default root-resource pushdown of simple FILTER, ORDER BY and LIMIT/OFFSET. An ORDER BY variable not in the SELECT list is refused.

## Lower-level API: `InMemory`

```elixir
mapping = AshR2RML.Resource.Info.mapping!(MyApp.Person)

{:ok, observation} =
  AshR2RML.OBDA.InMemory.query(MyApp.Person, mapping, "SELECT ?s WHERE { ?s ?p ?o }",
    actor: actor,
    tenant: tenant
  )

{:ok, graph} = AshR2RML.OBDA.InMemory.materialize(MyApp.Person, mapping, actor: actor)
```

`query_many/3` and `materialize_many/2` take a list of `{ash_resource, mapping}` specs and merge them into one graph, so one SPARQL query can traverse relationships.

## Defaults and opt-ins

- `authorize?` defaults to `true`; `:actor`, `:tenant`, `:context`, `:domain`, `:action` flow to the Ash read.
- `authorize?: false` is refused unless `allow_unauthorized: true` is also passed.
- `sensitive?: true` attributes are refused unless `allow_sensitive: true`.
- `require_authorizer: true` refuses resources without `Ash.Policy.Authorizer`.
- `require_tenant: true` refuses multitenant reads with no `:tenant`.
- `previous_graph: graph` on `materialize_many/2` returns `%{graph: graph, delta: delta}`.

Refusals are `{:error, %AshR2RML.Refusal{}}`, never silent skips.

## Limits

Only `:template` and `:column` subject strategies materialize. Many-to-many join-table relationships refuse with `REFUSED_UNSUPPORTED_SPARQL_FEATURE`.

## One-subject invariant

Ash and SPARQL observe the same persisted subject through the same Ash read. There is no dual-write path and no second authoritative graph store.

## Verification

A real test must:

1. create records through real Ash actions;
2. run `InMemory.query/4` with the intended actor/tenant;
3. normalize results by semantic IRI and RDF term value;
4. compare them to the same subject observed through Ash.

A generated R2RML file alone is `PARTIAL_ALIVE`. The generated Turtle is for external R2RML consumers; this package ships no engine for it.

## Not shipped in the Hex package

`lib/mix/**` (mix tasks, Igniter installer) and `bench/` are excluded from the package files list in `mix.exs`; only `lib/**/*.ex` outside `lib/mix/`, `usage-rules/`, README, LICENSE, CHANGELOG, `AGENTS.md` and `usage-rules.md` ship.
