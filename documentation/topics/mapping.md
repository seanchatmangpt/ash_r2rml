# mapping

AshR2RML compiles Ash resource metadata plus the `r2rml` DSL into a normalized mapping IR
(`AshR2RML.Mapping.*`). The IR is the input to the R2RML renderer and to
`AshR2RML.OBDA.InMemory`. No Java and no JDBC are involved in this path.

## DSL

```elixir
use Ash.Resource, extensions: [AshR2RML.Resource]

r2rml do
  class "http://xmlns.com/foaf/0.1/Person"
  subject template: "http://example.com/person/{id}"
  property :name, "http://xmlns.com/foaf/0.1/name"
  property :age, "http://xmlns.com/foaf/0.1/age",
    datatype: "http://www.w3.org/2001/XMLSchema#integer"
  reference :company, "http://example.com/worksFor"
  graph "http://example.com/graph/people"
end
```

Section options: `table_name`, `sql_query`, `schema`. Table and column names are derived
from the Ash resource when omitted.

| Entity | Arguments and options |
|---|---|
| `class` | one IRI or a list of IRIs (`rdf:type` for every subject) |
| `subject` | exactly one of `template`, `column`, `constant`; `term_type: :iri \| :blank_node` |
| `property` | attribute, predicate IRI; `datatype`, `language`, `language_column`, `constant`, `template`, `term_type: :literal \| :iri \| :blank_node` |
| `reference` | relationship, predicate IRI; `inverse_predicate`, `direction: :outgoing \| :incoming`, `guard_class` |
| `graph` | IRI; `scope: :resource \| :subject` |

A `sparql` section declares named queries: `query :name, form: :select`, with `form` one of
`:select`, `:construct`, `:ask`, `:describe`.

Rules enforced at compile time:

- A `subject` is required. A `:blank_node` subject may omit template, column and constant.
- `language` and `language_column` require a literal term map.
- A property on an unknown attribute, or a reference to a missing relationship, fails
  compilation with a typed refusal (see `refusals.md`).

## IR

`AshR2RML.Resource.Info.mapping/1` returns the persisted `AshR2RML.Mapping.Resource`;
`mapping_result/1` returns `{:ok, mapping} | {:error, %AshR2RML.Refusal{}}`; `mapping!/1`
raises `ArgumentError`. `domain_resources/1` lists the resources of a domain that carry the
extension.

| Struct | Fields |
|---|---|
| `Mapping.Resource` | `ash_resource`, `logical_table`, `subject_map`, `class_iris`, `predicate_object_maps`, `reference_object_maps`, `graph_maps`, `identities`, `metadata` |
| `Mapping.SubjectMap` | `strategy` (`:template`, `:column`, `:constant`, `:blank_node`), `value`, `term_type`, `graph_maps` |
| `Mapping.PredicateObjectMap` | `attribute`, `predicate_iri`, `object_map`, `graph_maps` |
| `Mapping.ObjectMap` | `strategy` (`:column`, `:template`, `:constant`), `value`, `datatype`, `language`, `term_type`, `graph_maps` |
| `Mapping.ReferenceObjectMap` | `relationship`, `predicate_iri`, `inverse_predicate`, `parent_resource`, `joins`, `graph_maps`, `metadata` |
| `Mapping.JoinCondition` | `child`, `parent` (column names) |
| `Mapping.LogicalTable` | `table_name`, `sql_query`, `schema` |

## Subject.to_iri and from_iri

`AshR2RML.Subject` converts between key values and subject IRIs for `:template` subject
maps. Both functions accept a `Mapping.Resource` or a resource module.

```elixir
AshR2RML.Subject.to_iri(mapping, %{id: "a b"})
#=> {:ok, "http://ex.org/p/a%20b"}

AshR2RML.Subject.from_iri(mapping, "http://ex.org/p/a%20b")
#=> {:ok, %{id: "a b"}}
```

- `to_iri/2` takes a struct, map or keyword list. Values are percent-encoded with
  `URI.encode/2` and `URI.char_unreserved?/1`, the same encoding `OBDA.InMemory` uses. A
  missing or nil template field refuses with `:REFUSED_INVALID_TERM_MAP`.
- `from_iri/2` inverts the template. It refuses templates with adjacent placeholders, IRIs
  that do not match the template, malformed percent-encoding, and any capture that does not
  re-encode to the same IRI.
- A non-template subject strategy refuses with `:UNSUPPORTED_TERM_TYPE`.
- `iri_only?/1` and `check_iri_only/1` return false or `:UNSUPPORTED_TERM_TYPE` when the
  subject, an object map or a reference uses a blank-node term type.

## See Also

`obda.md` · `refusals.md`
