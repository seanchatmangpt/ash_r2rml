# Legacy path: vectors

AshR2RML does not own vector storage, vector indexes, or similarity-query execution.

If an application maps vector-like data into RDF, it must do so through an explicit custom datatype or structured semantic representation with deterministic lexical semantics.

See [Custom Ash types](custom-types.md) and [Datatypes](datatypes.md).

Do not infer RDF semantics from a database vector type or embedding dimension alone. Storage/query representation and semantic representation are different contracts.

This file remains only as a compatibility path for donor-era usage rules.
