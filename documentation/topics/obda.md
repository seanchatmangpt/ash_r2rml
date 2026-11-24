# obda

`AshR2RML.OBDA.InMemory` answers SPARQL over Ash resources inside the BEAM. It uses zero
Java and zero JDBC. It reads rows with `Ash.read/2`, builds an `RDF.Graph` from the mapping
IR, and runs the query with `AshR2RML.SPARQL.Local`. It works with any Ash data layer, since
it adds no data-layer check of its own.

## API

```elixir
alias AshR2RML.OBDA.InMemory

mapping = AshR2RML.Resource.Info.mapping!(MyApp.Person)

{:ok, graph} = InMemory.materialize(MyApp.Person, mapping, actor: user)
{:ok, obs} = InMemory.query(MyApp.Person, mapping, "SELECT ?s WHERE { ?s ?p ?o }", actor: user)

specs = [{MyApp.Person, person_mapping}, {MyApp.Org, org_mapping}]
{:ok, obs} = InMemory.query_many(specs, sparql, actor: user)
```

`materialize_many/2` merges several resources into one graph. A `ReferenceObjectMap` becomes
an object-property triple when its parent resource is in the same call; the parent's subject
template is filled with each join column's child value (single or composite key). A
reference whose parent is absent, whose FK is nil, or whose result is not a valid IRI
produces no triple.

Passing `previous_graph: graph` returns `{:ok, %{graph: graph, delta: delta}}`, where
`delta` is `AshR2RML.Delta.diff/2` of old against new.

## Read options

| Option | Behavior |
|---|---|
| `:actor`, `:tenant`, `:context`, `:domain`, `:action` | passed to `Ash.Query.for_read/4`; `:action` defaults to the primary read |
| `:authorize?` | defaults to `true` |
| `:allow_unauthorized` | must be `true` to run with `authorize?: false`, else refusal |
| `:require_authorizer` | `true` refuses a resource without `Ash.Policy.Authorizer` |
| `:require_tenant` | `true` refuses a multitenant resource read with no `:tenant` |
| `:allow_sensitive` | `true` permits materializing `sensitive?: true` attributes |

Every Ash read error (forbidden, invalid, unknown) and every guard failure returns
`{:error, %AshR2RML.Refusal{code: :REFUSED_UNSUPPORTED_SPARQL_FEATURE}}`, with the guard or
error class in `detail` and `evidence`.

## Omission and sensitive fields

- A field denied by a field policy comes back from Ash as `%Ash.ForbiddenField{}`; an
  unloaded field as `%Ash.NotLoaded{}`. Both are omitted: no triple is emitted. A template
  subject with such a field yields no subject for that row.
- `Security.sanitize_in_memory_mapping/2` runs before any read result reaches graph
  construction. A mapped field that no longer resolves to an Ash attribute (for example an
  encrypted attribute replaced by a decrypting calculation) is absent from the mapping.
- A mapped attribute marked `sensitive?: true`, or one used in a subject template, subject
  column or join child column, refuses with `:REFUSED_SENSITIVE_ATTRIBUTE_MATERIALIZATION`
  unless `allow_sensitive: true`.
- Subject maps other than `:template` and `:column`, and `:join_table` many-to-many
  references (`joins: []`), refuse with `:REFUSED_UNSUPPORTED_SPARQL_FEATURE`.
- Template substitution percent-encodes values. A `:column` subject whose stored value is
  not a valid IRI skips that row.

## Row ordering and hashing

Without `ORDER BY` in the query text, SELECT rows are sorted canonically (each row's
bindings sorted, then rows sorted), so output does not depend on data-layer scan order. With
`ORDER BY` the engine's order is kept. The observation metadata carries
`engine: :in_memory_ets`.

`AshR2RML.SPARQL.Result.hash_rows/1` normalizes rows as a multiset
(`AshR2RML.Parity.normalize_multiset/1`), encodes them with
`:erlang.term_to_binary/2` (`:deterministic`) and returns the lowercase hex SHA-256. Equal
multisets give equal hashes regardless of row order.

## See Also

`mapping.md` · `refusals.md`
