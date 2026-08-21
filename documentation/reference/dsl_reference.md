# AshR2RML DSL Reference

This document provides a technical specification for the `r2rml` Spark DSL extension added to `Ash.Resource`.

---

## Extension Setup

To enable the DSL in an Ash resource, add `AshR2RML.Resource` to your `extensions` list:

```elixir
use Ash.Resource,
  extensions: [AshR2RML.Resource]
```

---

## Top-Level `r2rml` Block

The `r2rml` block configures resource-level RDF class mapping, subject IRI generation, and query sections.

```elixir
r2rml do
  class "https://schema.org/Person"

  subject do
    template "https://example.org/people/{id}"
    term_type :iri
  end
end
```

### Options

| Section / Option | Type | Required | Description |
|---|---|---|---|
| `class` | `String.t()` | Yes | The RDF class IRI (`rr:class`) assigned to mapped subjects. |
| `subject` | block | Yes | Configures subject map term generation rules. |

---

## `subject` Block

Configures `rr:subjectMap` rules.

```elixir
subject do
  template "https://example.org/people/{id}"
  term_type :iri
  class "https://schema.org/Person"
end
```

### Options

| Option | Type | Default | Description |
|---|---|---|---|
| `template` | `String.t()` | `nil` | IRI template with `{attribute_name}` placeholders. |
| `column` | `String.t()` | `nil` | Direct database column name to use as subject IRI. |
| `term_type` | `:iri` \| `:blank_node` | `:iri` | R2RML term type (`rr:IRI` or `rr:BlankNode`). |

---

## `rdf` Block on Attributes

Annotates Ash attributes with RDF predicate metadata.

```elixir
attributes do
  attribute :name, :string do
    rdf do
      predicate "http://xmlns.com/foaf/0.1/name"
      datatype "http://www.w3.org/2001/XMLSchema#string"
    end
  end
end
```

### Options

| Option | Type | Required | Description |
|---|---|---|---|
| `predicate` | `String.t()` | Yes | RDF predicate IRI (`rr:predicate`). |
| `datatype` | `String.t()` | No | Explicit XSD datatype IRI (`rr:datatype`). Inferred from Ash type if omitted. |
| `language` | `String.t()` | No | RDF language tag (e.g. `"en"`). Cannot be combined with `datatype`. |

---

## `rdf` Block on Relationships

Annotates Ash relationships (`belongs_to`, `has_one`, `has_many`, `many_to_many`) with RDF object property metadata.

```elixir
relationships do
  belongs_to :organization, MyApp.Organization do
    rdf do
      predicate "https://schema.org/memberOf"
    end
  end
end
```

### Options

| Option | Type | Required | Description |
|---|---|---|---|
| `predicate` | `String.t()` | Yes | RDF object property predicate IRI (`rr:predicate`). |
| `join_condition` | block | No | Explicit child/parent column overrides if auto-derivation is insufficient. |

---

## `sparql` Block

Configures optional declarative SPARQL query helpers.

```elixir
r2rml do
  sparql do
    query :all_people, """
      SELECT ?person ?name WHERE {
        ?person a <https://schema.org/Person> ;
                <http://xmlns.com/foaf/0.1/name> ?name .
      }
    """
  end
end
```
