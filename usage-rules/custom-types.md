# Custom Ash types

AshR2RML supports custom Ash types only through an explicit semantic datatype contract.

## Contract

A custom mapping must define enough information to manufacture a deterministic RDF term:

- RDF datatype IRI or explicit IRI/literal term strategy;
- lexical serialization;
- optional lexical validation/parsing used by tests;
- nullability behavior inherited from the Ash attribute;
- any storage assumptions required to connect the Ash value to a relational column.

## No `inspect/1` serialization

Never use Elixir `inspect/1`, JSON encoding, or arbitrary stringification as an implicit RDF lexical form.

Those may be valid explicit application choices, but they must be declared as such.

## Structured values

Maps, embedded resources, vectors, geometry values, money values, units, and other structured types require domain-appropriate mappings. Lawful choices may include:

- a dedicated RDF datatype;
- decomposition into related resources/properties;
- controlled-vocabulary IRIs;
- a standards-defined lexical representation;
- explicit unsupported status.

AshR2RML does not preserve structure by hiding it inside an opaque literal unless that is the admitted semantic representation.

## Registry

Custom mappings register through the public AshR2RML datatype extension/registry rather than patching the R2RML renderer.

The renderer consumes normalized datatype mapping IR and should not contain application-specific type branches.

## Verification

Every custom mapping needs round-trip/conformance fixtures proving the emitted lexical form and datatype are stable and understood by the selected OBDA/RDF test path.
