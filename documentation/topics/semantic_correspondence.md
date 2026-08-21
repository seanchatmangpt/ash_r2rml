# Conceptual Architecture: Core Semantic Correspondence

This document explains the conceptual foundations of mapping Ash Framework resources to W3C R2RML mappings and RDF graphs.

---

## 1. The One-Subject Invariant

In an integrated enterprise system, data observed through Ash resources, SQL queries, and SPARQL endpoints represents **one single domain reality**.

```text
Ash.Resource + RDF metadata
           │
           ▼
    AshR2RML.Mapping (IR)
       ╱         ╲
Relational       R2RML Turtle
  State            │
 (AshPostgres)    OBDA Engine
      ╲           ╱
       ONE SUBJECT
```

AshR2RML does not duplicate data into a graph database or triplestore. Instead, it generates standards-compliant W3C R2RML mappings that allow virtual RDF query engines (OBDA) to execute SPARQL directly over relational persistence (managed by `AshPostgres`).

---

## 2. Theoretical Semantic Projection Matrix

Every concept in the RDF/OWL open-world semantics maps to a corresponding construct in Ash's closed-world resource definition and the relational model:

```text
RDF / OWL Domain            Ash Resource Model           Relational Database (SQL)
────────────────────        ──────────────────────       ─────────────────────────
Class (owl:Class)           Ash.Resource                 Database Table / View
Datatype Property           Attribute                    Column / Expression
Object Property             Relationship                 Foreign Key / Join Table
Subject Identity            Subject Template / Identity  Primary / Unique Key(s)
RDF Datatype                Ash.Type                     SQL Column Type
Required Value              allow_nil? false             NOT NULL Constraint
```

---

## 3. Closed Operational SHACL Closure

While OWL ontologies operate under the **Open-World Assumption (OWA)**, relational databases and application code require deterministic, closed boundaries (**Closed-World Assumption - CWA**).

When generating Ash resources from ontologies (ontology-first workflow), raw OWL is insufficient. `AshR2RML` relies on **SHACL operational shapes** to supply operational closure:

1. **Closed Fields:** SHACL defines explicit property lists allowed on a resource.
2. **Cardinality Constraints:** `sh:minCount` and `sh:maxCount` map to `allow_nil?` and relationship types (`belongs_to` vs `has_many`).
3. **Datatype Binding:** `sh:datatype` enforces deterministic Ash scalar type mapping.

---

## 4. Summary

By maintaining clean ownership boundaries—Ash owning resource actions, AshPostgres owning SQL persistence, AshR2RML owning semantic IR compilation, and OBDA engines owning virtual SPARQL execution—AshR2RML guarantees semantic consistency across Elixir code, SQL databases, and RDF knowledge graphs.
