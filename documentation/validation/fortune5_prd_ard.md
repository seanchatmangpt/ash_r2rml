<!--
SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Fortune 5 Enterprise Semantic Mapping & OBDA Architecture Specification

**Document Identifier**: `DOC-F5-PRD-ARD-2026.1`  
**Classification**: Enterprise Architecture Standard  
**Status**: Formally Approved & Machine-Verified  
**Effective Date**: 2026-08-21  

---

## 1. Executive Summary & Product Invariants

### 1.1 Product Purpose
`AshR2RML` is the enterprise-grade semantic mapping compiler bridging declarative Elixir resource modeling ([Ash Framework](https://ash-hq.org)) with the W3C Relational-to-RDF Mapping Language ([W3C R2RML](https://www.w3.org/TR/r2rml/)). It enables Ontology-Based Data Access (OBDA), virtual Knowledge Graph materialization, fine-grained semantic security filtering, and automated evidence qualification across Fortune 5 heterogeneous IT estates.

### 1.2 Absolute Product Invariant
> **AshR2RML is NOT an `Ash.DataLayer`, graph database, triplestore, SPARQL engine, or application ontology.**

`AshR2RML` compiles Ash resource metadata, action definitions, calculation expressions, aggregate relations, and explicit semantic annotations into a normalized, deterministic Intermediate Representation (`AshR2RML.Mapping.IR`) and standards-compliant W3C R2RML Turtle documents. Existing Ash data layers (`AshPostgres`, `Ash.DataLayer.Ets`, etc.) retain exclusive ownership over relational persistence and SQL execution.

```text
Ash.Resource + Semantic Metadata
             │
             ▼
      AshR2RML.Mapping (Normalized IR)
         ╱         ╲
        ▼           ▼
 Relational Schema   R2RML Mapping (*.ttl)
   (AshPostgres)     (W3C Standard)
        │                   │
        └─────────┬─────────┘
                  ▼
         ONE PHYSICAL SUBJECT
       Ash / SQL / SPARQL (OBDA)
```

---

## 2. The Five Semantic Worlds

Enterprise semantic verification, compliance attestation, and autonomic saga execution in `AshR2RML` are formulated over five distinct, mathematically rigorous semantic worlds:

```text
                      ┌────────────────────────────────────────┐
                      │    1. Requirement Graph (G_req)        │
                      │   - W3C SHACL Operational Shapes       │
                      │   - W3C ODRL 2.2 Policies & Duties     │
                      │   - W3C SKOS Taxonomies & Controlled   │
                      └──────────────────┬─────────────────────┘
                                         │ Governs Admission
                                         ▼
┌───────────────────────────────────┐        ┌───────────────────────────────────┐
│   2. Manufactured System (S_mfg)  │        │   3. Observed System (G_obs)      │
│  - Ash Resources & Domains        │───────>│  - IEEE/W3C OCEL 2.0 Event Logs   │
│  - Reactor Orchestration Sagas    │ Emits  │  - W3C SOSA/SSN Metric Probes     │
│  - Relational DDL & ETS Stores    │ Traces │  - QUDT Latency / SLO Quantities  │
└─────────────────┬─────────────────┘        └─────────────────┬─────────────────┘
                  │                                            │
                  │ Compiles via AshR2RML                      │
                  ▼                                            │
┌───────────────────────────────────┐                          │
│ 4. Projected Semantic Graph       │                          │
│          (G_proj)                 │                          │
│  - W3C R2RML Virtual Triples      │                          │
│  - Ontop Virtual SPARQL Views     │                          │
│  - Dynamic Actor Policy Redaction │                          │
└─────────────────┬─────────────────┘                          │
                  │                                            │
                  └──────────────────────┬─────────────────────┘
                                         │ Evaluates Compliance
                                         ▼
                      ┌────────────────────────────────────────┐
                      │   5. Qualification Graph (G_qual)      │
                      │  - W3C EARL 1.0 Machine Assertions     │
                      │  - SPDX 3.0 Cryptographic Provenance   │
                      │  - Non-Circular Verification Proofs    │
                      └────────────────────────────────────────┘
```

### 2.1 World 1: Requirement Graph ($G_{req}$)
- **Definition**: The formal, declarative specification of enterprise business rules, operational admission criteria, security constraints, and SLA thresholds.
- **Standards Used**:
  - **W3C SHACL** (`http://www.w3.org/ns/shacl#`): Operational shapes enforcing multi-region topologies, replication lag bounds (<1000ms), credential rotation duties, and audit trail completeness.
  - **W3C ODRL 2.2** (`http://www.w3.org/ns/odrl/2/`): Digital rights, permissions, prohibitions, and operational duties.
  - **W3C SKOS** (`http://www.w3.org/2004/02/skos/core#`): Controlled vocabularies and domain taxonomies.
  - **W3C DXWG PROF** (`http://www.w3.org/ns/dx/prof/`): Profile binding public standard ontologies into an authoritative enterprise application profile (`priv/ontologies/fortune5/fortune5_profile.ttl`).

### 2.2 World 2: Manufactured System ($S_{mfg}$)
- **Definition**: The executable software and persistence topology realized in code and configuration.
- **Components**:
  - Declarative Ash Resources (`CostCenter`, `GeneralLedger`, `JournalEntry`, `EnterpriseAccount`, `ODRLAsset`, `DatabaseReplica`).
  - Action definitions with strict validation, calculations (`gross_margin_percentage`, `risk_weighted_balance`), and aggregates (`total_debits`, `total_credits`).
  - Multi-step fault-tolerant transactional sagas orchestrated via `Reactor` (`BlueGreenDeploymentSaga`, `DatabaseFailoverSaga`, `CredentialRotationSaga`).
  - Physical persistence layers (PostgreSQL relational tables in production; in-memory `Ash.DataLayer.Ets` for fast unit mapping isolation).

### 2.3 World 3: Observed System Graph ($G_{obs}$)
- **Definition**: The empirical telemetry, execution traces, and audit streams emitted by $S_{mfg}$ during operation.
- **Standards Used**:
  - **IEEE / W3C OCEL 2.0**: Object-Centric Event Logs capturing qualified Event-to-Object (`:target`, `:initiator`, `:actor`, `:input`, `:output`) and Object-to-Object (`:dependsOn`, `:memberOf`, `:relatesTo`) multigraph topologies with dynamic time-varying attributes.
  - **W3C SOSA / SSN** (`http://www.w3.org/ns/sosa/`): Sensor observations capturing operational telemetry (P99 latencies, error rates, CPU load).
  - **QUDT** (`http://qudt.org/schema/qudt/`): Computational measurements rigorously tagged with standard units (`unit:MilliSEC`, `unit:BYTE`, `unit:PERCENT`).
  - **W3C TIME** (`http://www.w3.org/2006/time#`): Temporal instants and duration intervals.

### 2.4 World 4: Projected Semantic Graph ($G_{proj}$)
- **Definition**: The virtual RDF Knowledge Graph exposed dynamically by compiling $S_{mfg}$ into W3C R2RML mappings without physical data copying.
- **Mechanisms**:
  - Deterministic generation of `rr:TriplesMap`, `rr:SubjectMap`, `rr:PredicateObjectMap`, and `rr:RefObjectMap`.
  - Multi-hop relational foreign key joins (`rr:joinCondition` on `rr:child` and `rr:parent`).
  - Dynamic actor-based policy redaction (`AshR2RML.Policy.filter_for_actor/3`) mitigating semantic visibility gaps between database storage and SPARQL endpoints.

### 2.5 World 5: Qualification Graph ($G_{qual}$)
- **Definition**: Machine-verifiable audit trails, evaluation reports, and cryptographic receipts proving that $G_{obs}$ and $G_{proj}$ satisfy all constraints in $G_{req}$.
- **Standards Used**:
  - **W3C EARL 1.0** (`http://www.w3.org/ns/earl#`): Formal test assertions (`earl:Assertion`) with explicit outcomes (`earl:passed`, `earl:failed`, `earl:cantTell`).
  - **SPDX 3.0** (`https://spdx.org/rdf/3.0.0/terms/`): Software Bill of Materials (SBOM) and SHA-256 cryptographic verification checksums for every artifact and event trace.
  - **W3C DQV** (`http://www.w3.org/ns/dqv#`): Data quality and completeness metrics.

---

## 3. Ontology Responsibility Matrix

The Fortune 5 application profile (`f5prof`) establishes authoritative responsibility boundaries across standard public ontologies:

| Standard Ontology | Namespace IRI | Enterprise Semantic Responsibility |
|---|---|---|
| **W3C ORG** | `http://www.w3.org/ns/org#` | Organizational structure, business units, divisions, executive roles, and memberships. |
| **W3C SKOS** | `http://www.w3.org/2004/02/skos/core#` | Controlled taxonomies, classification codes, data sensitivity schemes. |
| **W3C ODRL 2.2** | `http://www.w3.org/ns/odrl/2/` | Access control permissions, regulatory prohibitions, credential rotation duties. |
| **P-Plan** | `http://purl.org/net/p-plan#` | Declarative process plans, multi-step saga execution graphs, step dependencies. |
| **W3C SOSA / SSN** | `http://www.w3.org/ns/sosa/`, `.../ssn/` | System telemetry, observability probes, actuator execution, observations. |
| **W3C TIME** | `http://www.w3.org/2006/time#` | Temporal intervals, SLA evaluation windows, rotation periods. |
| **QUDT 2.1** | `http://qudt.org/schema/qudt/` | Scientific & computational measurement units (`unit:MilliSEC`, `unit:BYTE`, `unit:PERCENT`). |
| **SPDX 3.0** | `https://spdx.org/rdf/3.0.0/terms/` | Software supply chain provenance, SBOM manifests, cryptographic artifact checksums. |
| **W3C DQV** | `http://www.w3.org/ns/dqv#` | Dataset quality dimensions, precision evaluations, schema conformance scores. |
| **W3C DCAT 3** | `http://www.w3.org/ns/dcat#` | Data catalogs, dataset boundaries, distribution endpoints, data services. |
| **W3C EARL 1.0** | `http://www.w3.org/ns/earl#` | Machine-executable test assertions, conformance evaluation reports. |
| **W3C R2RML** | `http://www.w3.org/ns/r2rml#` | Relational-to-RDF mapping triples maps, subject maps, predicate-object maps, joins. |
| **W3C SHACL** | `http://www.w3.org/ns/shacl#` | Operational admission gates, multi-region topological constraints, SLA shapes. |

---

## 4. Architectural Decision Records (ADRs)

### ADR-01: Non-Circular Verification Law
- **Context**: In traditional architectures, systems verify their own compliance using internal models, leading to tautological assertions and unprovable compliance.
- **Decision**: All compliance proofs must be produced across independent world boundaries. $G_{req}$ (SHACL/ODRL) is defined independently of $S_{mfg}$ (Ash/PostgreSQL). The running system emits empirical evidence $G_{obs}$ (OCEL 2.0 / SOSA). Independent evaluators project $G_{proj}$ (R2RML / Ontop) and assert $G_{qual}$ (EARL / SPDX).
- **Consequence**: Compliance claims are verifiable by external third-party auditors and independent SPARQL engines without trusting application runtime internals.

### ADR-02: Strict Separation of Persistence vs Semantic Mapping
- **Context**: Merging semantic mapping logic into custom data layers couples RDF vocabularies to specific storage engines.
- **Decision**: `AshR2RML` compiles strictly into a normalized Intermediate Representation (`AshR2RML.Mapping.IR`) and W3C R2RML Turtle. Relational persistence is delegated entirely to standard data layers (`AshPostgres`, `Ash.DataLayer.Ets`).
- **Consequence**: Full compatibility with standard Ash tooling, transaction managers, Ecto migrations, and third-party OBDA engines (e.g. Ontop).

### ADR-03: Typed Semantic Refusals Over Silent Fallbacks
- **Context**: Incomplete or ambiguous semantic mappings (e.g., unmapped custom types, missing join foreign keys) can silently corrupt generated RDF graphs or default to invalid string serializations.
- **Decision**: `AshR2RML` mandates fail-closed typed refusals (e.g., `REFUSED_UNMAPPED_DATATYPE`, `UNSUPPORTED_ASH_TYPE`, `REFUSED_NON_UNIQUE_SEMANTIC_IDENTITY`).
- **Consequence**: Mapping errors are caught deterministically at compilation or bundle assembly time rather than corrupting downstream SPARQL queries.

### ADR-04: Mitigation of the OBDA Semantic Visibility Gap
- **Context**: Relational databases often store sensitive columns in tables accessible to standard SQL users. If an OBDA engine exposes the complete schema via R2RML, unprivileged SPARQL users could query sensitive fields.
- **Decision**: Implement `AshR2RML.Policy.filter_for_actor/3`, which prunes `PredicateObjectMap` entries according to `Ash.Policy.Authorizer` rules before rendering the actor-specific R2RML bundle.
- **Consequence**: Dynamic, actor-aware R2RML generation guarantees that unprivileged SPARQL endpoints receive zero triples for unauthorized attributes, even if those columns exist in the underlying PostgreSQL database.

---

## 5. Clean-Room Event Stream Replay & Process Mining

`AshR2RML` implements the IEEE/W3C OCEL 2.0 standard for clean-room operational replay and process conformance checking (van der Aalst Process Science):

1. **Clean-Room State Reconstruction**: Complete system state can be deterministically replayed from an empty state solely by ingesting the signed OCEL 2.0 event stream.
2. **Order-Independent Deterministic Convergence**: Asynchronous or out-of-order event ingestion converges on an identical cryptographic state checksum (`sha256_term/1`).
3. **Process Conformance Checking**:
   - Trace fitness ($fitness = 1.0$) for authorized execution pathways.
   - Immediate detection and rejection of unapproved deployment sequences (e.g., deploying without change request approval).
   - Detection of missing mandatory audit steps.
