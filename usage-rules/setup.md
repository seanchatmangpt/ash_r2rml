# Setup

AshR2RML is a semantic mapping extension for Ash. It does not replace your data layer.

## Dependencies

A typical relational application uses AshR2RML beside AshPostgres:

```elixir
def deps do
  [
    {:ash, "~> 3.0"},
    {:ash_postgres, "~> 2.0"},
    {:ash_r2rml, "~> 1.0"}
  ]
end
```

AshR2RML itself owns no database connection pool and requires no graph database.

## Resource configuration

Keep the existing data layer and add the AshR2RML extension:

```elixir
defmodule MyApp.Person do
  use Ash.Resource,
    domain: MyApp.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshR2RML.Resource]

  postgres do
    table "people"
    repo MyApp.Repo
  end

  r2rml do
    class "https://schema.org/Person"

    subject do
      template "https://example.org/people/{id}"
      term_type :iri
    end
  end
end
```

## Formatter and docs

Add AshR2RML's Spark extension to formatter/cheat-sheet generation when the package installer has not already done so. Prefer the package's Igniter installer when available so formatter and documentation configuration stay synchronized with the installed version.

## R2RML output

Compile one or more resources to the normalized mapping IR and render Turtle:

```elixir
resources = [MyApp.Person]
{:ok, ttl} = AshR2RML.R2RML.render(resources)
File.write!("priv/r2rml/application.ttl", ttl)
```

Generated R2RML is a projection. Do not hand-edit it when the owning Ash resource or ontology-first generator can regenerate it.

## OBDA engine

AshR2RML generates mappings but does not execute SPARQL. Configure a compatible R2RML/OBDA engine separately and point it at:

1. the same relational database used by the Ash application; and
2. the generated R2RML mapping.

The intended topology is one persisted subject with multiple query surfaces, not synchronized databases.

## Ontology-first projects

Ontology-first consumers use the shipped ggen pack as a development-time manufacturer:

```text
ontology/profile + SHACL
        ↓
       ggen
        ↓
generated Ash resources
        ↓
     AshR2RML
```

ggen is not required merely to execute a normal Ash application using already-generated resources.
