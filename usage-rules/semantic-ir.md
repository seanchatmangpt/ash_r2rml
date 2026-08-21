# Semantic mapping IR

Every AshR2ML entry path converges on one normalized intermediate representation before serialization.

## Why an IR exists

Do not let resource DSL, ontology-first generation, and R2RML rendering each carry their own partially duplicated model. Normalize once so validation, documentation, deterministic rendering, and testing all observe the same mapping subject.

## Canonical concepts

The public model includes equivalents of:

```text
AshR2ML.Mapping.Resource
AshR2ML.Mapping.SubjectMap
AshR2ML.Mapping.PredicateObjectMap
AshR2ML.Mapping.ReferenceObjectMap
AshR2ML.Mapping.JoinCondition
AshR2ML.Mapping.Datatype
AshR2ML.Mapping.GraphMap
```

## Resource mapping

A resource mapping contains at least:

- Ash resource identity;
- one or more RDF class IRIs;
- logical relational source;
- subject map;
- scalar property maps;
- relationship/reference maps;
- optional graph maps.

## Normalization

Normalization must resolve convenience DSL forms into explicit structures. For example, an Ash `belongs_to` plus an RDF predicate becomes a reference-object mapping with an explicit destination mapping and join condition before R2RML rendering begins.

## Determinism

IR equality must not depend on map iteration order, loaded-module order, or process timing. Normalize collections with stable semantic ordering.

## Introspection

`AshR2ML.Resource.Info.mapping/1` exposes the normalized mapping so callers and tests can inspect semantic structure without depending on raw Spark DSL internals.

## Renderer isolation

The R2RML renderer consumes the IR. It must not rediscover Ash relationships, infer table names, or decide datatype mappings independently. If the IR is insufficient to render a valid mapping, fix the IR/compiler boundary rather than adding hidden renderer inference.

## Extensibility

New mapping capabilities should extend the IR first, then DSL/introspection, validation, renderer, docs, and tests in that order. This keeps all entry paths coherent.
