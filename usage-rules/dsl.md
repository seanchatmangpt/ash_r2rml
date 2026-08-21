# AshR2RML DSL

The DSL describes semantic information that Ash and the active data layer cannot infer on their own. It should not duplicate relational metadata unnecessarily.

## Resource mapping

```elixir
r2rml do
  class "https://schema.org/Person"

  subject do
    template "https://example.org/people/{id}"
    term_type :iri
  end
end
```

A resource may map to one or more RDF classes when the mapping is explicit and lawful. Class IRIs must be absolute IRIs.

## Subject maps

Supported subject strategies are:

- template;
- column/attribute;
- constant IRI;
- blank node when explicitly requested.

A template may reference only real mapped attributes. Missing fields are compile-time errors.

Subject identity is semantic identity, not merely Ash's primary key. AshR2RML may use an Ash identity to prove uniqueness, but it does not assume every database key is automatically the correct public RDF identifier.

## Attribute mapping

```elixir
attribute :name, :string do
  rdf do
    predicate "http://xmlns.com/foaf/0.1/name"
  end
end
```

AshR2RML derives the relational column/source and default RDF datatype when that information is provable. Override the RDF datatype only when the semantic type differs lawfully from the default registry mapping.

Representative options:

```elixir
rdf do
  predicate "https://example.org/amount"
  datatype "http://www.w3.org/2001/XMLSchema#decimal"
  term_type :literal
end
```

Language-tagged literals and constants are supported only through explicit mapping forms. Do not overload ordinary Ash scalar attributes with implicit language semantics.

## Relationship mapping

```elixir
belongs_to :organization, MyApp.Organization do
  rdf do
    predicate "https://schema.org/memberOf"
  end
end
```

AshR2RML introspects the Ash relationship and data-layer metadata to derive a reference object map and join. Users should not repeat `source_attribute`, `destination_attribute`, or parent map identity unless inference is impossible or an explicit override is required.

If a relationship cannot be mapped without inventing a join or identity, compilation fails.

## Graph maps

Named-graph output may be configured at resource or property level when required. Default behavior is the default RDF graph.

Graph configuration changes RDF placement, not relational persistence.

## Logical tables

For ordinary AshPostgres resources, AshR2RML derives the logical table from the resource/data-layer configuration.

Explicit logical SQL views/queries are an advanced mapping surface and must be deterministic, read-only semantic projections. They do not grant AshR2RML authority to mutate database schema or bypass the active data layer.

## Introspection

The public introspection entry point exposes the normalized mapping rather than raw Spark DSL state:

```elixir
mapping = AshR2RML.Resource.Info.mapping(MyApp.Person)
```

Consumers that need to inspect semantics should depend on `AshR2RML.Mapping` structures, not implementation-specific Spark entities.

## Validation

The DSL fails closed for invalid or incomplete semantic mappings. Representative failures include invalid IRIs, missing subject maps, unmapped datatypes, missing relationship predicates, ambiguous joins, and non-unique semantic identities.

Do not add convenience defaults that silently weaken these checks.
