# Ontology-first generation

Ontology-first AshR2RML starts from an admitted RDF/OWL vocabulary plus an application profile and SHACL operational shapes.

## Compilation boundary

Do not compile arbitrary OWL directly into Ash or SQL.

Use:

```text
ontology
   ↓
application profile
   ↓
SHACL operational shapes
   ↓
ggen
   ↓
generated Ash resources
   ↓
AshR2RML.Mapping
```

OWL/RDFS supplies semantics. SHACL/profile facts provide the operational closure required to choose attributes, relationship cardinalities, identities, and storage strategies.

## Resource generation

A `sh:NodeShape` targeting an admitted class may generate an Ash resource when the profile supplies enough information to determine the module/domain and relational projection.

A property shape may generate an Ash attribute or relationship depending on `sh:datatype`, `sh:class`, cardinality, and explicit mapping metadata.

## Ambiguity

If multiple Ash/relational models remain lawful, generation must not pick one arbitrarily. Preserve alternatives while evaluating constraints, then either select deterministically or return a typed refusal.

Representative refusals include ambiguous relationship storage, missing semantic identity, unsupported datatype, and insufficient cardinality information.

## Equivalence

Do not manufacture `owl:equivalentClass` or `owl:equivalentProperty` from naming similarity. Preserve weaker alignment relations as weaker relations.

## Generated source

Generated Ash files are projections. Their authority is the ontology/profile/shapes plus ggen queries/templates. Fix generation upstream and rerun; do not maintain semantic truth in generated Elixir manually.

## Round trip

The ontology-first crown is not source generation. It is:

```text
RDF/SHACL
   ↓
ggen
   ↓
Ash
   ↓
relational persistence
   ↓
R2RML
   ↓
OBDA/SPARQL
```

with stable semantic identity, scalar values, and relationships preserved for the admitted fixture/query fragment.
