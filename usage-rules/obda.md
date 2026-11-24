# OBDA and virtual RDF

`AshR2RML.OBDA.InMemory` is the only runtime OBDA backend. It is in-process and works with any Ash data layer. No SQL-rewriting engine, JDBC driver, or Java component is shipped.

## Architecture

```text
SPARQL
   ↓
AshR2RML.OBDA.InMemory
   ↓
Ash.read/2 (policies, tenancy, field redaction apply)
   ↓
RDF.Graph → SPARQL engine → Observation
```

## API

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
