# Getting Started with AshR2RML

This tutorial guides you through creating your first Ash resource annotated with `AshR2RML` metadata, compiling it into a normalized semantic mapping IR, rendering standards-valid W3C R2RML Turtle, and validating the resulting RDF output.

---

## What You Will Build

You will create a `MyApp.User` resource with attributes (`:name`, `:email`) and a relationship to `MyApp.Organization`, mapped to `https://schema.org/Person`, `http://xmlns.com/foaf/0.1/name`, `https://schema.org/email`, and `https://schema.org/memberOf`.

```text
Ash.Resource (MyApp.User)
           │
           ▼
    AshR2RML Compiler
           │
           ▼
    AshR2RML.Mapping IR
           │
           ▼
  W3C R2RML Turtle Output
```

---

## Prerequisites

Ensure your `mix.exs` includes `:ash` and `:ash_r2rml`:

```elixir
def deps do
  [
    {:ash, "~> 3.0"},
    {:ash_r2rml, "~> 0.1.0"}
  ]
end
```

---

## Step 1: Define Mapped Ash Resources

Create the `MyApp.Organization` resource first:

```elixir
defmodule MyApp.Organization do
  use Ash.Resource,
    domain: MyApp.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshR2RML.Resource]

  postgres do
    table "organizations"
    repo MyApp.Repo
  end

  r2rml do
    class "https://schema.org/Organization"

    subject do
      template "https://example.org/organizations/{id}"
      term_type :iri
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false

      rdf do
        predicate "https://schema.org/name"
      end
    end
  end
end
```

Next, define `MyApp.User` referencing `MyApp.Organization`:

```elixir
defmodule MyApp.User do
  use Ash.Resource,
    domain: MyApp.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshR2RML.Resource]

  postgres do
    table "users"
    repo MyApp.Repo
  end

  r2rml do
    class "https://schema.org/Person"

    subject do
      template "https://example.org/users/{id}"
      term_type :iri
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false

      rdf do
        predicate "http://xmlns.com/foaf/0.1/name"
      end
    end

    attribute :email, :string do
      rdf do
        predicate "https://schema.org/email"
      end
    end
  end

  relationships do
    belongs_to :organization, MyApp.Organization do
      attribute_writable? true

      rdf do
        predicate "https://schema.org/memberOf"
      end
    end
  end
end
```

---

## Step 2: Compile Resource into Normalized Mapping IR

Inspect the resource mapping programmatically using `AshR2RML.Mapping`:

```elixir
# Introspect resource and construct normalized mapping IR
{:ok, mapping} = AshR2RML.Mapping.from_resource(MyApp.User)

IO.inspect(mapping.class)
# => "https://schema.org/Person"

IO.inspect(mapping.subject_map.template)
# => "https://example.org/users/{id}"
```

---

## Step 3: Render W3C R2RML Turtle

Pass the compiled mapping into `AshR2RML.R2RML.Renderer` to generate valid Turtle:

```elixir
{:ok, turtle} = AshR2RML.R2RML.Renderer.render(mapping)

IO.puts(turtle)
```

### Generated Turtle Output Example

```turtle
@prefix rr: <http://www.w3.org/ns/r2rml#> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

<#UserMapping>
    rr:logicalTable [ rr:tableName "users" ] ;
    rr:subjectMap [
        rr:template "https://example.org/users/{id}" ;
        rr:class <https://schema.org/Person>
    ] ;
    rr:predicateObjectMap [
        rr:predicate <http://xmlns.com/foaf/0.1/name> ;
        rr:objectMap [ rr:column "name" ; rr:datatype xsd:string ]
    ] ;
    rr:predicateObjectMap [
        rr:predicate <https://schema.org/email> ;
        rr:objectMap [ rr:column "email" ; rr:datatype xsd:string ]
    ] ;
    rr:predicateObjectMap [
        rr:predicate <https://schema.org/memberOf> ;
        rr:objectMap [
            rr:parentTriplesMap <#OrganizationMapping> ;
            rr:joinCondition [
                rr:child "organization_id" ;
                rr:parent "id"
            ]
        ]
    ] .
```

---

## Step 4: Verify Mapping Laws

Verify your mapping conforms to core AshR2RML invariant laws:

1. **Datatype Law:** Ensure attribute types map directly to explicit XSD types.
2. **Relationship Law:** Ensure foreign key joins match between physical columns (`organization_id` → `id`).
3. **Identity Law:** Confirm every template placeholder (`{id}`) matches a real mapped attribute.

---

## Next Steps

- Explore [Ash-First Mapping How-To](../how_to/ash_first.livemd) for complex query setups.
- Read [Ontology-First How-To](../how_to/ontology_first.livemd) to generate resources from SHACL shapes.
- Check the [DSL Reference](../reference/dsl_reference.md) for full configuration options.
