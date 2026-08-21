# ggen manufacturing

AshR2ML uses ggen as a development-time semantic manufacturer. ggen is not required merely to run an Ash application that already contains generated resources.

## Pack shape

The ontology-first pack follows the normal ggen structure:

```text
ontology.ttl
profile/ and/or shapes/
queries/*.rq
gates/*.rq
templates/*
ggen.toml
```

The exact directories may evolve with ggen conventions, but ontology/query/template ownership and fail-closed gates are mandatory.

## Source authority

The authority order is:

```text
ontology/application profile
        ↓
SHACL operational shape
        ↓
compiler mapping facts
        ↓
SPARQL queries / gates
        ↓
templates
        ↓
generated Ash/R2RML surfaces
```

Generated artifacts never outrank their semantic sources.

## Gates

Generation must fail before writes when required mapping facts are absent or contradictory. Gates should cover at least:

- missing class mapping;
- missing semantic identity;
- unsupported datatype;
- unresolved relationship target;
- ambiguous relationship storage;
- invalid subject template;
- join target without stable identity;
- generated module/table collision;
- unproven ontology equivalence.

## Determinism

Run `ggen sync` twice from the same admitted inputs and require identical generated semantic surfaces. Receipt timestamps or other explicitly declared run metadata may be excluded from byte comparison.

## No bespoke shadow generator

Do not hide application-specific RDF transforms in shell scripts or ad-hoc Elixir code when they belong in the ontology, SPARQL query, gate, template, or a general ggen capability.

If ggen lacks a required generic transformation:

1. prove the limitation with a focused fixture;
2. add the smallest general capability to ggen;
3. verify it in ggen;
4. consume it from the AshR2ML pack.

## Runtime boundary

The generated Ash code and AshR2ML runtime mapping must not require ggen to answer normal application queries. ggen participates in construction, not ordinary request-time persistence or SPARQL execution.
