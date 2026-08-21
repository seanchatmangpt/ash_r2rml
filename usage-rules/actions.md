# Actions and mutations

AshR2RML maps semantic structure. It does not grant execution authority and does not redefine Ash actions.

## Ash actions remain application behavior

Create, update, destroy, read, custom actions, atomics, policies, and transactions continue to belong to Ash and the active data layer.

AshR2RML may describe the RDF classes/properties of resources affected by those actions, but an RDF predicate or ontology class never becomes an executable capability by implication.

## No action-to-class collapse

Do not automatically turn verbs into RDF classes or persistent resources simply because an application exposes an action with that name.

For example, `approve` is ordinarily an Ash action. If the domain also models an `Approval` or `Decision` as durable data, that resource is mapped independently through its own semantic contract.

## Provenance

Applications may explicitly model executions, requests, decisions, receipts, or provenance entities and map them using ordinary AshR2RML resource/relationship mappings. AshR2RML does not synthesize a provenance ledger for every action automatically.

## Writes and virtual RDF

When an Ash action changes relational state, subsequent SPARQL queries through the OBDA/R2RML path observe the new relational state because the RDF graph is a virtual projection over the same database.

AshR2RML does not dual-write triples to keep a graph database synchronized.

## Authority

Ontology facts, generated mappings, SHACL constraints, and R2RML are descriptive/constructive artifacts. They carry no ambient authority to run migrations, execute Ash actions, or mutate external systems.
