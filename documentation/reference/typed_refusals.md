# AshR2RML Typed Refusals Catalog

AshR2RML strictly enforces fail-closed compilation laws. When invalid, incomplete, or ambiguous semantic annotations are encountered, compilation fails with an explicit typed refusal exception rather than falling back to unproven assumptions.

---

## Refusal Exception Catalog

### `REFUSED_INVALID_CLASS_IRI`
- **Cause:** The `class` specified in the `r2rml` block is not a valid absolute IRI (must begin with a valid scheme e.g. `http://` or `https://`).
- **Fix:** Provide a fully qualified HTTP/HTTPS IRI.

---

### `REFUSED_MISSING_SUBJECT_MAP`
- **Cause:** A resource lacks a `subject` block defining a template or column mapping.
- **Fix:** Add a `subject` block inside `r2rml` with a valid `template` or `column`.

---

### `REFUSED_NON_UNIQUE_SEMANTIC_IDENTITY`
- **Cause:** Template placeholders in subject maps (e.g. `{id}`) reference non-unique or non-existent attributes.
- **Fix:** Ensure template variables map to attributes marked with primary keys or unique identities.

---

### `REFUSED_UNMAPPED_DATATYPE` / `UNSUPPORTED_ASH_TYPE`
- **Cause:** An attribute uses a custom or unknown Ash type for which no explicit XSD datatype mapping exists in `AshR2RML.Mapping.Datatype`.
- **Fix:** Register an explicit datatype mapping contract for the custom Ash type. Automatic conversion to `xsd:string` is explicitly illegal under the Datatype Law.

---

### `REFUSED_AMBIGUOUS_RELATIONSHIP`
- **Cause:** An Ash relationship carries an RDF predicate, but source/destination key introspection yields multiple or conflicting join targets.
- **Fix:** Explicitly declare `destination_attribute` or provide an explicit `join_condition` block.

---

### `REFUSED_INVALID_JOIN_CONDITION`
- **Cause:** The physical child or parent column specified in a join condition does not exist in the corresponding database table schema.
- **Fix:** Verify attribute column names match table migrations.

---

### `REFUSED_RELATIONSHIP_WITHOUT_PREDICATE`
- **Cause:** A relationship is included in semantic export without an explicit `rdf` predicate annotation.
- **Fix:** Annotate the relationship with `rdf do predicate "..." end` or exclude it from semantic mapping.

---

### `REFUSED_UNPROVEN_EQUIVALENCE`
- **Cause:** Ontology-first manufacture attempts to infer `owl:equivalentClass` or `owl:equivalentProperty` without explicit operational SHACL proof.
- **Fix:** Provide explicit equivalence facts in the input SHACL profile.

---

### `UNSUPPORTED_TERM_TYPE`
- **Cause:** An invalid term type atom was specified (valid term types are `:iri` and `:blank_node`).
- **Fix:** Update `term_type` to `:iri` or `:blank_node`.
