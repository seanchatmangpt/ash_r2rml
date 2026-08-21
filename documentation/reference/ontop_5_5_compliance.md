# Ontop 5.5.0 compliance contract

AshR2RML pins Ontop 5.5.0 as the external OBDA conformance engine used by the real PostgreSQL/R2RML crown. AshR2RML does not absorb Ontop's execution authority: the compiler remains SELECT/CONSTRUCT-only, while Ontop owns SPARQL-to-SQL rewriting and virtual RDF query execution.

The machine-readable contract lives in `AshR2RML.OBDA.Ontop.Compliance`. It is derived from Ontop's standards-compliance page as updated 2026-07-21 and deliberately preserves the upstream supported/unsupported/limited distinctions.

## Coverage carried into the repository

| Surface | Contract |
|---|---|
| SPARQL 1.1 | 93 listed supported features and 8 listed unsupported features, with DBMS-dependent limitations retained |
| GeoSPARQL 1.0 | 37 listed supported functions/terms and 32 listed unsupported properties/terms; metre, radian, and degree units retained |
| R2RML | documented as almost fully compliant; Base IRIs, default mapping generation, and binary SQL datatype normalization remain explicit exceptions |
| RDF 1.1 | simple-literal `xsd:string` and language-literal `rdf:langString` behavior retained |
| Ontop time functions | `ofn:*` and `obdaf:*` capability list plus dialect-specific restrictions retained |
| Ontop 5.5.0 additions | `xsd:date` and `obdaf:queryId` are represented in the public capability profile |

The Ontop source currently declares aggregate coverage as `6/6` while listing seven aggregate function names. AshR2RML stores both the published coverage string and the seven names; it does not silently rewrite the source.

## Admission law

Use:

    AshR2RML.OBDA.Ontop.Compliance.require_supported(:sparql_1_1, "SELECT")

before manufacturing a plan that depends on a specific Ontop capability.

A fully supported feature returns an admitted capability record pinned to Ontop 5.5.0. Unsupported or unknown capabilities return typed refusals:

- `REFUSED_OBDA_CAPABILITY_UNSUPPORTED`
- `REFUSED_OBDA_CAPABILITY_UNKNOWN`

R2RML's three published exceptions therefore never become accidental "supported by adjacency" claims.

## Verification

`test/ontop_compliance_test.exs` verifies the exact feature inventory, exclusions, dialect limitations, typed capability admission, and that every published supported SPARQL/GeoSPARQL section has a live probe family.

`test/integration/ontop_compliance_crown.exs` executes those read-only probe families against the pinned official Ontop 5.5.0 image and a PostGIS-backed PostgreSQL database. The crown includes query forms, expressions, aggregates, property paths, RDF 1.1 literal behavior, Ontop time functions, and GeoSPARQL relation/function families.

The crown writes `tmp/ash_r2rml_ontop_compliance/compliance-receipt.json`. That receipt proves observed execution only for the pinned source/mapping/database/engine topology. It does not grant migration, mutation, deployment, or cutover authority.

## Explicit exclusions remain first-class

Ontop's documented SPARQL exclusions are not probed as though an observed failure could replace the upstream contract. They remain typed, inspectable exclusions, including `SERVICE`, unbounded/optional property-path repetition, `STRDT`, `STRLANG`, `timezone`, and user-defined functions.

Likewise, unsupported GeoSPARQL topology vocabulary properties, GeoGeometry metadata properties, and GML serialization remain explicit exclusions even though related query functions are supported.
