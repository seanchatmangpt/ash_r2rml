<!--
SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Why AshR2RML: semantic/graph capability without a database decision

This document is written for the person who has to decide whether "we need to query our data
as a graph" turns into a new database project. It makes one claim, and every number in it is
from a real, reproducible run in this repository (`bench/RESULTS.md`), not a projection.

## The reframe

The default assumption on hearing "we need SPARQL / RDF / graph queries" is: *we need to adopt
a graph database.* That assumption bundles two separate decisions into one: (1) what shape of
query do we need, and (2) where does the data live. Most teams only actually need the first —
a way to ask relationship- and ontology-shaped questions of data they already have — and get
sold the second as a package deal: a new storage engine, a new operational surface, a new
source-of-truth question (does the graph database or the relational database win a conflict?),
and a migration project measured in quarters before the first real query runs.

**AshR2RML's premise: semantic query capability is a mapping decision, not a storage decision.**
It compiles the Ash resources you already have into a normalized mapping IR once
(`AshR2RML.Mapping`), and that one IR gives you two independent, standards-based ways to ask
graph-shaped questions of that same data — without moving it, duplicating it, or standing up
a new system of record.

## What the status quo actually costs (measured, not assumed)

Adopting a dedicated graph database to answer graph-shaped questions means: new infrastructure
to operate, a data-sync problem between it and your relational system of record (ETL, CDC, or
dual-writes — all three are real ongoing failure surfaces), and a multi-week-to-multi-quarter
project before the first query runs against real data.

Compare that to what this repository's own benchmark measured for the *narrowest possible*
version of "add graph capability" — an existing Ash resource, zero new infrastructure:

| Path | Time to first real SPARQL query result |
|---|---|
| `AshR2RML.OBDA.InMemory` over an existing `Ash.DataLayer.Ets` resource | **4–52 ms**, in-process, zero external infrastructure |
| `AshR2RML.OBDA.Ontop` virtual graph over an existing `AshPostgres` resource | Minutes to configure (R2RML mapping + JDBC properties); ~1.9–2.0 s per query in a naive per-invocation deployment, dominated entirely by container/JVM start, not by query execution or data volume |
| Adopt a dedicated graph database | New infrastructure, a data-sync architecture decision, and typically weeks before the first production query — before any query-speed question is even reachable |

The middle row is the honest, unflattering one, and it's included on purpose: **even a mature,
purpose-built OBDA engine has real invocation overhead** when deployed the way most teams first
try it (one container per query). That overhead is architectural (external process per call),
not a verdict on relational-to-RDF query rewriting as a category — a persistent Ontop server
removes nearly all of it. The point isn't "AshR2RML's SPARQL engine beats Ontop's" (a
category error `bench/RESULTS.md` explicitly refuses to make); it's that **the expensive part
of every one of these architectures is the same thing — getting a correct projection from your
real data to a graph shape — and AshR2RML already did that part for any Ash resource you have
today.**

## The two real execution surfaces, not one theoretical one

- **Prototype and test in milliseconds, in-process.** `AshR2RML.OBDA.InMemory` materializes
  real Ash rows (via real `Ash.read!/2`, so real Ash authorization applies) into a real
  `RDF.Graph` and runs full SPARQL — SELECT, ASK, CONSTRUCT, DESCRIBE — through `SPARQL.ex`. No
  container, no JVM, no network round trip. It supports real cross-resource joins
  (`materialize_many/2`/`query_many/3`) resolved from the same `reference_object_maps` R2RML
  itself uses, so a relationship query written today is the same query that runs against
  production later.
- **Deploy the same mapping to production without moving data.** The identical mapping IR
  renders standards-valid W3C R2RML Turtle, which Ontop (or any R2RML-compliant OBDA engine)
  executes as a virtual RDF graph directly over your existing PostgreSQL tables — no ETL, no
  second copy of the data, no drift between "the graph" and "the real data."

Both surfaces are exercised by the same test suite against the same mapping, so a query that's
correct in-process during development is correct against production Ontop+Postgres by
construction, not by hope.

## This was adversarially tested, not just built

Two real hardening passes this session are worth knowing about, because they're the difference
between a demo and something you'd put in front of a security review:

1. **Ash field-policy authorization carries through to the RDF projection for real.** A
   `field_policy`-denied attribute comes back from Ash as a sentinel value, not `nil`; the
   in-process materializer correctly omits it rather than leaking or crashing on it — verified
   against a real field-policy-protected attribute, both as the denied actor (field absent)
   and the authorized actor (field present).
2. **A confirmed, then closed, structural gap between the two execution surfaces.** Ontop
   connects to PostgreSQL directly over JDBC with no concept of an Ash actor — confirmed live,
   against a real Postgres+Ontop stack, that a field-policy-protected column mapped into R2RML
   is returned in full with zero actor context. `AshR2RML.Security.sanitize_mapping/2` now
   removes any such attribute from the mapping automatically before it can ever reach that
   path, rather than leaving it as a footnote someone has to remember.

Both are unit-tested against real Ash resources and real field policies, not mocked
interactions.

## What this is not claiming

AshR2RML is not a graph database, does not attempt to replace one for genuinely graph-native
workloads (deep multi-hop traversal, graph algorithms, graph-shaped storage as the primary
access pattern), and does not benchmark itself against one — see `bench/README.md`'s explicit
scope. The claim is narrower and, for most teams asking "do we need a graph database," more
useful: **if what you need is standards-based, relationship-aware, ontology-shaped access to
data that already lives in Ash-modeled resources, you can have it today, from the resources
you already wrote, without a database migration project.**

## Try it

```bash
mix test test/obda_in_memory_test.exs        # in-process SPARQL over a real Ash.DataLayer.Ets resource
MIX_ENV=test mix run bench/obda_query_latency.exs   # the numbers above, reproduced on your machine
```
