# Relationships

Ash relationships are the source of relational joins and RDF object-property mappings.

## Object-property mapping

```elixir
relationships do
  belongs_to :organization, MyApp.Organization do
    allow_nil? false

    rdf do
      predicate "https://schema.org/memberOf"
    end
  end
end
```

AshR2RML compiles the relationship into a reference object map when the active data layer exposes a deterministic relational join.

Conceptually:

```text
Ash relationship
      │
      ├── relational FK/join
      └── rr:RefObjectMap
             └── rr:joinCondition
```

## What is inferred

Prefer introspection over repeated configuration. AshR2RML should derive, when available:

- destination resource;
- source attribute;
- destination attribute;
- table/view identity;
- destination triples map;
- join columns;
- relationship cardinality represented by Ash.

The RDF predicate is semantic information and is normally explicit.

## `belongs_to`

A relational `belongs_to` normally maps cleanly to a reference object map from the child/source table to the parent triples map.

The join must target a stable parent identity. A foreign key existing in SQL is necessary evidence but does not by itself define the public RDF predicate or subject strategy.

## `has_one` and `has_many`

Reverse Ash relationships are mapped from the same admitted relational relation. Do not manufacture an unrelated second relation simply because Ash exposes both directions.

When an inverse RDF predicate is declared, preserve the explicit inverse semantics. Do not infer `owl:inverseOf` merely from the presence of two Ash relationships.

## Many-to-many

Many-to-many mappings must follow the actual relational join structure. A plain join table may compile to chained/reference maps. If the join relation carries its own semantic attributes, provenance, validity interval, role, or identity, model it as an association resource instead of erasing those facts into a bare edge.

## Association resources

Use an association resource when the relationship is itself a thing with data:

```text
Person ── Membership ── Organization
             │
             ├── role
             ├── valid_from
             └── provenance
```

This preserves information that a direct object property cannot carry on its own.

## Missing mappings

A relationship with an RDF predicate may never be silently omitted from the mapping IR or R2RML output.

Refuse when:

- the destination resource has no usable subject map;
- join metadata is ambiguous;
- source/destination attributes cannot be resolved;
- the active data layer does not expose a lawful relational projection;
- an ontology-first shape remains ambiguous about storage/cardinality.

## Cardinality

R2RML itself describes mapping, not all SHACL cardinality semantics. AshR2RML preserves Ash's actual relationship shape and, in ontology-first workflows, ggen uses SHACL to select the Ash/relational projection before R2RML compilation.

Do not claim that `rr:RefObjectMap` alone enforces `sh:minCount` or `sh:maxCount`.

## Tests

Relationship tests must prove the same semantic edge at three levels when applicable:

1. Ash relationship metadata;
2. relational FK/join data;
3. RDF/SPARQL result through generated R2RML.

Matching a generated Turtle substring is not sufficient evidence for the integration crown.
