# Semantic identities

AshR2RML treats database identity and RDF subject identity as related but distinct concepts.

## Subject identity

Every resource emitted as an RDF subject requires a deterministic subject map. Common strategies are:

```elixir
r2rml do
  subject do
    template "https://example.org/orders/{tenant_id}/{id}"
    term_type :iri
  end
end
```

or an explicitly selected attribute/column/constant strategy.

A subject template is valid only when every placeholder resolves to a mapped attribute and the resulting identifier is stable for the intended semantic lifetime.

## Ash identities

Ash identities are useful evidence that the fields used by a semantic subject are unique. They do not automatically become RDF identity.

```elixir
identities do
  identity :external_identity, [:tenant_id, :external_id]
end
```

A mapping may build an IRI from those fields when the semantic contract explicitly selects them.

## Primary keys

Primary keys are physical/application identity. They may be used in a subject template, but AshR2RML never assumes that every primary key should be published as a semantic IRI.

This distinction matters when internal UUIDs, tenant-local keys, natural keys, and public identifiers have different lifetimes.

## Reference-object joins

A relationship mapped through `rr:RefObjectMap` must be able to target the parent triples map deterministically. Join columns/attributes must identify the intended parent mapping without ambiguity.

If the destination mapping cannot prove a stable target identity, return a typed refusal rather than emitting a join that may identify the wrong RDF subject.

## Collision checks

Tests must cover subject collisions across:

- composite templates;
- tenant partitions;
- nullable components;
- formatting/canonicalization rules;
- custom datatype lexical forms.

Two distinct admitted resources must not silently manufacture the same subject IRI unless the mapping deliberately asserts they are the same RDF subject.

## Blank nodes

Blank nodes are opt-in. Do not use blank nodes as a fallback for missing identity information.

## Identity drift

Changing a table name, module name, migration, or internal database key must not change RDF subject identity unless that value is explicitly part of the subject contract.

Semantic identity changes are breaking semantic changes and must be visible in review, generated mappings, tests, and release notes.
