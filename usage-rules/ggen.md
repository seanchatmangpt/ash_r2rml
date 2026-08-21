# ggen manufacturing

AshR2RML uses ggen as a development-time semantic manufacturer. ggen is not required merely to run an Ash application that already contains generated resources.

## Ash-first cloud pack shape

For cloud ggen, Ash is the maintained semantic source. Do not maintain a second ontology or operational-profile TTL tree beside the Ash resources.

AshR2RML compiles the admitted Ash dependency closure into `AshR2RML.Mapping.Bundle`, then emits the ggen TTL projections deterministically:

```text
Ash.Resource + AshR2RML metadata
        ↓
AshR2RML.Mapping.Bundle
        ├── ontology.ttl
        ├── shapes/operational-profile.ttl
        └── r2rml/mapping.ttl
        ↓
ggen queries / gates / templates
```

Use `AshR2RML.compile_ash_ttl_bundle/1` to obtain the path/content graph. The function does not write files or invoke ggen; cloud ggen owns materialization and actuation.

The returned TTL files are generated projections. They are not editing surfaces and must not be checked in as independently maintained semantic sources.

## Ontology-first import remains lawful

External RDF/OWL + SHACL remains a supported ingress topology when an external ontology is genuinely authoritative. That path is:

```text
external ontology/application profile
        ↓
SHACL operational shape
        ↓
AshR2RML admission
        ↓
canonical Mapping IR
        ↓
generated Ash.Resource
```

Once the resulting Ash resources become the admitted application source for cloud ggen, subsequent cloud-ggen TTL is emitted back from the Ash mapping graph. Do not create a manually synchronized loop of Ash plus hand-edited TTL.

## Source authority

For Ash-first cloud generation the authority order is:

```text
Ash resource semantics
        ↓
canonical Mapping IR
        ↓
TTL projections
        ↓
SPARQL queries / gates
        ↓
templates
        ↓
generated application surfaces
```

Generated artifacts never outrank their admitted Ash/mapping source.

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

Call `AshR2RML.compile_ash_ttl_bundle/1` twice for the same admitted Ash resource closure and require identical file maps and SHA-256 identities. After materialization, run ggen twice and require identical generated semantic surfaces except for explicitly declared receipt metadata.

## No bespoke shadow generator

Do not hide application-specific RDF transforms in shell scripts or ad-hoc cloud files when the facts already exist in AshR2RML.Mapping.

If ggen lacks a required generic transformation:

1. prove the limitation with a focused fixture;
2. add the general capability to the proper compiler/ggen layer;
3. verify it there;
4. consume the deterministic path/content graph from cloud ggen.

## Runtime boundary

The generated Ash code and AshR2RML runtime mapping must not require ggen to answer normal application queries. ggen participates in construction, not ordinary request-time persistence or SPARQL execution.
