# AshR2RML Normalized Mapping IR Reference

The normalized mapping IR (`AshR2RML.Mapping`) is the intermediate representation that bridges Ash resource metadata and W3C R2RML rendering.

---

## Architectural Role

```text
Ash.Resource + DSL
       │
       ▼
AshR2RML.Mapping (IR) ◄─── (Single Deterministic Contract)
       │
       ▼
AshR2RML.R2RML.Renderer
```

All public compilation paths normalize into these structs before rendering output.

---

## Struct Definitions

### `AshR2RML.Mapping.Resource`

Top-level container representing an annotated resource mapping.

```elixir
%AshR2RML.Mapping.Resource{
  module: module(),
  table_name: String.t(),
  class: String.t(),
  subject_map: AshR2RML.Mapping.SubjectMap.t(),
  predicate_object_maps: [AshR2RML.Mapping.PredicateObjectMap.t()],
  reference_object_maps: [AshR2RML.Mapping.ReferenceObjectMap.t()],
  graph_map: AshR2RML.Mapping.GraphMap.t() | nil
}
```

---

### `AshR2RML.Mapping.SubjectMap`

Represents `rr:subjectMap` details.

```elixir
%AshR2RML.Mapping.SubjectMap{
  template: String.t() | nil,
  column: String.t() | nil,
  term_type: :iri | :blank_node,
  class: String.t()
}
```

---

### `AshR2RML.Mapping.PredicateObjectMap`

Represents scalar attribute predicate-object mappings (`rr:predicateObjectMap`).

```elixir
%AshR2RML.Mapping.PredicateObjectMap{
  predicate: String.t(),
  column: String.t(),
  datatype: String.t() | nil,
  language: String.t() | nil
}
```

---

### `AshR2RML.Mapping.ReferenceObjectMap`

Represents relationship predicate-object mappings referencing parent triple maps (`rr:parentTriplesMap`).

```elixir
%AshR2RML.Mapping.ReferenceObjectMap{
  predicate: String.t(),
  parent_resource: module(),
  parent_triples_map_id: String.t(),
  join_conditions: [AshR2RML.Mapping.JoinCondition.t()]
}
```

---

### `AshR2RML.Mapping.JoinCondition`

Represents column equality constraints for relationship joins (`rr:joinCondition`).

```elixir
%AshR2RML.Mapping.JoinCondition{
  child_column: String.t(),
  parent_column: String.t()
}
```

---

### `AshR2RML.Mapping.Datatype`

Represents XSD/RDF datatype conversion definitions.

```elixir
%AshR2RML.Mapping.Datatype{
  ash_type: module() | atom(),
  xsd_iri: String.t(),
  to_lexical: (any() -> String.t()),
  from_lexical: (String.t() -> any())
}
```

---

### `AshR2RML.Mapping.GraphMap`

Represents named target graph assertions (`rr:graphMap`).

```elixir
%AshR2RML.Mapping.GraphMap{
  template: String.t() | nil,
  iri: String.t() | nil
}
```
