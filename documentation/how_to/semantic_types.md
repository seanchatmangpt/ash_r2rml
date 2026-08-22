# Semantic types from public ontologies

AshR2RML treats public semantic value spaces as the authority and Ash types as executable projections. The semantic type compiler is SELECT/CONSTRUCT only: it does not apply migrations, write application data, invoke ggen, or grant production authority.

## Architecture

Public ontology terms and application-profile constraints are admitted into a content-addressed `AshR2RML.SemanticType.Plan`. XSD, RDF, SKOS, QUDT, GeoSPARQL, and OWL-Time are built-in providers. Additional providers implement `AshR2RML.SemanticType.Provider`.

DfCM preserves lawful representations before selection:

- literal: builtin, NewType, custom type, registry;
- IRI: NewType, custom type, registry;
- SKOS concept: custom type, registry, resource;
- structured value: composite, embedded, JSONB, resource;
- identity-bearing resource: resource.

A plan may select one candidate explicitly. Unknown terms, invalid selections, and attempts to collapse value objects into scalar R2RML datatypes are typed refusals.

## Runtime types

The library provides executable Ash types for RDF IRIs, `rdf:langString`, SKOS concept identity, QUDT quantity values, and OWL-Time intervals. The generalized `AshR2RML.Type` contract also exposes semantic kind, datatype/class/scheme IRI, SHACL constraints, RDF encoding, and RDF decoding while preserving the original `xsd_datatype` and lexical callbacks for compatibility.

## Mix

    mix ash_r2rml.types.inspect IRI [IRI...]
    mix ash_r2rml.types.plan PROFILE.json
    mix ash_r2rml.types.manifest PROFILE.json
    mix ash_r2rml.types.verify PROFILE.json
    mix ash_r2rml.types.diff EXPECTED.json OBSERVED.json

These commands only inspect/construct data except `types.sync`, which delegates to the Igniter generator.

## Igniter

With Igniter available:

    mix ash_r2rml.gen.semantic_types PROFILE.json
    mix ash_r2rml.types.sync PROFILE.json

The task asks the pure compiler for an admitted plan, then writes the generated Elixir projection and `priv/semantic/semantic-types.json` through Igniter. Igniter does not reinterpret ontology semantics.

## Spark

Add `AshR2RML.SemanticTypes.Resource` beside `AshR2RML.Resource` when an Ash resource needs application-profile type selections. The `semantic_types` section is compiled into the same `SemanticType.Plan` and can be read through `AshR2RML.SemanticTypes.Resource.Info.plan/1`.

## ggen

`AshR2RML.Ggen.compile_semantic_types_bundle/2` returns a deterministic path/content graph containing the semantic manifest, generated Ash projection, generated contract test, and compilation receipt. AshR2RML never invokes ggen; ggen retains filesystem/render/replay/receipt authority.

The stable external seam is the semantic type manifest schema `https://ash-r2rml.dev/schema/semantic-type-plan/v1`.

## Verification

`AshR2RML.SemanticTypes.round_trip/2` executes Ash cast → native dump → stored load → RDF encode/decode → semantic equality for a specific admitted type/value. `diff/2` classifies drift as `ALIGNED`, `ONTOLOGY_AHEAD`, `ASH_AHEAD`, `AMBIGUOUS`, `LOSSY`, or `REFUSED`.

A successful in-memory round trip is evidence for that exact type/value only; it is not database, OBDA, deployment, or cutover evidence.
