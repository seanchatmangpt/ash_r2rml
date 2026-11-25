# Setup

AshR2RML is a semantic mapping extension for Ash. It does not replace your data layer.

## Dependencies

A typical relational application uses AshR2RML beside AshPostgres:

```elixir
def deps do
  [
    {:ash, "~> 3.0"},
    {:ash_postgres, "~> 2.0"},
    {:ash_r2rml, "~> 26.11"}
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

    subject template: "urn:uuid:{id}", term_type: :iri
  end
end
```

## Formatter and docs

Add AshR2RML's Spark extension to formatter/cheat-sheet generation when the package installer has not already done so. The Hex package ships no Igniter installer (`lib/mix` is excluded); add `AshR2RML.Resource` to `.formatter.exs` `import_deps`/`spark_locals_without_parens` by hand.

## R2RML output

Compile one or more resources to the normalized mapping IR and render Turtle:

```elixir
resources = [MyApp.Person]
{:ok, ttl} = AshR2RML.R2RML.render(resources)
File.write!("priv/r2rml/application.ttl", ttl)
```

Generated R2RML is a projection. Do not hand-edit it when the owning Ash resource can regenerate it.

## SPARQL runtime

`AshR2RML.OBDA.InMemory` is the only runtime backend. It reads through Ash (authorization on by default) and runs SPARQL in-process:

```elixir
mapping = AshR2RML.Resource.Info.mapping!(MyApp.Person)
{:ok, obs} = AshR2RML.OBDA.InMemory.query(MyApp.Person, mapping, sparql, actor: actor, tenant: tenant)
```

`authorize?: false` needs `allow_unauthorized: true`; `sensitive?: true` attributes need `allow_sensitive: true`. See [obda.md](obda.md). For the bounded envelope (`%Result{bindings, triples, stats, digest}`, `max_rows`, `max_triples`, `timeout_ms`, `max_heap_words`) use `AshR2RML.OBDA.query/3`.

## Subject IRIs

```elixir
id = "0b9f3c1e-6d2a-4f57-9a1b-3c8e5d7f2a41"
{:ok, iri} = AshR2RML.Subject.to_iri(MyApp.Person, id: id)
{:ok, %{id: ^id}} = AshR2RML.Subject.from_iri(MyApp.Person, iri)
```

## Syncing these rules into your project

Consumers pull this package's usage rules into their `AGENTS.md`/`CLAUDE.md` with the `usage_rules` package:

```bash
mix usage_rules.sync AGENTS.md --all --inline usage_rules:all --link-to-folder deps
```

Or run `mix usage_rules.sync` with your configured `usage_rules` options in `mix.exs`; re-run after upgrading `ash_r2rml`.
