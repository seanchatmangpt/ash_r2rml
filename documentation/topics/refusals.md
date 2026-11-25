# refusals

Failures are values: `{:error, %AshR2RML.Refusal{code, subject, detail, evidence}}`. Codes
come from the `AshR2RML.Refusal.code` type in `lib/ash_r2rml/mapping.ex`; OBDA runtime failures
and a few subject-IRI codes come from the separate `AshR2RML.Error` catalog (see
"AshR2RML.Error codes" below). Compile-time DSL
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
| `:REFUSED_INVALID_TERM_MAP` | term map invalid, including unsupported subject strategy, a non-string IRI or an unknown template field in `Subject` (templates that cannot be inverted use `:REFUSED_NON_INVERTIBLE_TEMPLATE`, below) |
| `:REFUSED_RELATIONSHIP_TARGET_UNMAPPED` | reference points at a resource with no mapping |
| `:UNSUPPORTED_TERM_TYPE` | term type not supported, including blank nodes where IRI-only is required |
| `:UNSUPPORTED_ASH_TYPE` | Ash type has no supported RDF correspondence: array types, NewType cycles or nesting too deep, `Ash.Type.Range` attributes, or types with no admitted datatype contract |
| `:REFUSED_UNSUPPORTED_SPARQL_FEATURE` | SPARQL feature or in-memory read not supported, including read guard failures |
| `:REFUSED_SENSITIVE_ATTRIBUTE_MATERIALIZATION` | `sensitive?: true` attribute would enter the RDF graph |
| `:REFUSED_ENCRYPTED_ATTRIBUTE_PROJECTION` | AshCloak-encrypted attribute would be projected in plaintext (subject, graph, object-template or reference-join map); map it as an opaque `urn:sha256:` pointer |
| `:REFUSED_PRIVATE_DATA_LAYER` | `OBDA.query/3` on a `private?: true` ETS resource; the worker process cannot read a private table |
| `:REFUSED_INVALID_OPTION` | `OBDA.Worker` option (`:timeout_ms`, `:max_heap_words`) is not a positive integer |
| `:REFUSED_NON_LITERAL_DATATYPE` | datatype applied to a non-literal term map |
| `:REFUSED_CHANGESET_CONFLICT` | changeset-derived triples conflict |
| `:REFUSED_MANIFEST_GENERATION` | manifest generation could not complete |
| `:REFUSED_RESOURCE_BOUND` | a resource bound was exceeded: SPARQL result rows over `:max_rows` (default 100,000; local and protocol queries), or a mapping closure over 10,000 resources (compiler) |

Meanings for codes not listed in the mapping validators are taken from the code names and
the call sites in `lib/ash_r2rml/mapping.ex`, `subject.ex`, `obda_in_memory.ex` and
`sparql.ex`.

## AshR2RML.Error codes

`%AshR2RML.Error{code, message, resource, field, sparql_clause, hint, details}` is an exception
struct built by `AshR2RML.Error.new/2` or converted from a refusal with `from_refusal/1`.
`AshR2RML.Error.codes/0` lists its catalog. Every code in the table above is also in that
catalog (except `:REFUSED_NON_INVERTIBLE_TEMPLATE`, listed here). Codes below appear only in
the `Error` catalog. Only `:REFUSED_QUERY_TIMEOUT` is `retryable?/1`.

| Code | Meaning |
|---|---|
| `:REFUSED_NON_INVERTIBLE_TEMPLATE` | `Subject.from_iri/2`: template has adjacent placeholders or a separator made only of characters that can occur inside an encoded value |
| `:REFUSED_MISSING_SUBJECT_KEY` | `Subject.to_iri/2`: a key the template references is nil, forbidden, not loaded or absent |
| `:REFUSED_INVALID_SUBJECT_IRI` | `Subject`: a segment fails `Ash.Type.cast_input/3` or the IRI does not match the template |
| `:REFUSED_RESULT_LIMIT_EXCEEDED` | result row limit exceeded |
| `:REFUSED_TRIPLE_LIMIT_EXCEEDED` | triple limit exceeded |
| `:REFUSED_MEMORY_LIMIT_EXCEEDED` | memory limit exceeded |
| `:REFUSED_QUERY_TIMEOUT` | query exceeded its time budget (retryable) |
| `:REFUSED_MISSING_TENANT` | tenant required but missing |
| `:REFUSED_UNAUTHORIZED` | actor is not authorized by the resource policies |
| `:REFUSED_READ_FAILED` | underlying Ash read failed; see `details.class` |
| `:REFUSED_WORKER_CRASHED` | OBDA query worker crashed; see `details.class` and `details.stacktrace` |
| `:REFUSED_INVALID_FEDERATION_ENVIRONMENT` | federation endpoint is not an absolute http or https URL with a public host |

## See Also

`mapping.md` · `obda.md`
