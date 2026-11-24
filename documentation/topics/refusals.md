# refusals

Failures are values: `{:error, %AshR2RML.Refusal{code, subject, detail, evidence}}`. Codes
come from the `AshR2RML.Refusal.code` type in `lib/ash_r2rml/mapping.ex`. Compile-time DSL
failures surface the code and detail in a `Spark.Error.DslError` message. There is no
silent fallback, for example no coercion of an unknown Ash type to string.

| Code | Meaning |
|---|---|
| `:REFUSED_INVALID_CLASS_IRI` | class IRI missing or not absolute |
| `:REFUSED_MISSING_SUBJECT_MAP` | no subject map, empty value, non-absolute constant subject, or no mapping on the resource |
| `:REFUSED_NON_UNIQUE_SEMANTIC_IDENTITY` | subject or join identity is not backed by a unique Ash identity |
| `:REFUSED_UNMAPPED_DATATYPE` | no RDF datatype mapping for the attribute's Ash type |
| `:REFUSED_AMBIGUOUS_RELATIONSHIP` | relationship missing or not uniquely resolvable |
| `:REFUSED_INVALID_JOIN_CONDITION` | join condition columns missing or invalid |
| `:REFUSED_RELATIONSHIP_WITHOUT_PREDICATE` | relationship mapped without a predicate IRI |
| `:REFUSED_R2RML_JOIN_WITHOUT_IDENTITY` | join references a parent with no identity to join on |
| `:REFUSED_UNPROVEN_EQUIVALENCE` | equivalence between two forms cannot be shown (also unsupported SPARQL result shape) |
| `:REFUSED_UNKNOWN_ATTRIBUTE` | mapping names an attribute the resource does not have |
| `:REFUSED_INVALID_LOGICAL_TABLE` | logical table missing or not exactly one of table or query |
| `:REFUSED_INVALID_GRAPH_MAP` | graph map empty, non-absolute, or of unsupported shape |
| `:REFUSED_INVALID_TERM_MAP` | term map invalid, including unsupported subject strategy and non-invertible subject IRIs |
| `:REFUSED_RELATIONSHIP_TARGET_UNMAPPED` | reference points at a resource with no mapping |
| `:UNSUPPORTED_TERM_TYPE` | term type not supported, including blank nodes where IRI-only is required |
| `:UNSUPPORTED_ASH_TYPE` | Ash type has no supported RDF correspondence |
| `:REFUSED_UNSUPPORTED_SPARQL_FEATURE` | SPARQL feature or in-memory read not supported, including read guard failures |
| `:REFUSED_SENSITIVE_ATTRIBUTE_MATERIALIZATION` | `sensitive?: true` attribute would enter the RDF graph |
| `:REFUSED_NON_LITERAL_DATATYPE` | datatype applied to a non-literal term map |
| `:REFUSED_CHANGESET_CONFLICT` | changeset-derived triples conflict |
| `:REFUSED_MANIFEST_GENERATION` | manifest generation could not complete |
| `:REFUSED_RESOURCE_BOUND` | result exceeds the row bound (default 100,000 rows) |

Meanings for codes not listed in the mapping validators are taken from the code names and
the call sites in `lib/ash_r2rml/mapping.ex`, `subject.ex`, `obda_in_memory.ex` and
`sparql.ex`.

## See Also

`mapping.md` · `obda.md`
