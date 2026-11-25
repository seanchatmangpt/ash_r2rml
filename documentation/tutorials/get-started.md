# get-started

Define an ETS-backed Ash resource, inspect its R2RML mapping, render Turtle, query it in
memory under an actor or tenant, and round-trip a subject IRI. Every snippet mirrors
`test/non_postgres_resource_test.exs`, `test/public_mapping_test.exs`,
`test/obda_in_memory_row_policy_tenant_test.exs` and `lib/ash_r2rml/subject.ex`.

## Add the dependency

```elixir
# mix.exs
defp deps do
  [
    {:ash_r2rml, "~> 26.11"}
  ]
end
```

Requires Elixir `~> 1.17` and `ash >= 3.28.0`. No data layer other than the one your
resource already uses is needed; AshPostgres is not a runtime requirement.

## Define a resource

Add `AshR2RML.Resource` to `extensions:` and describe the mapping in an `r2rml` block.

```elixir
defmodule MyApp.Domain do
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource MyApp.Widget
  end
end

defmodule MyApp.Widget do
  use Ash.Resource,
    domain: MyApp.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML.Resource]

  r2rml do
    class_iri("https://schema.org/Thing")
    subject_template("urn:uuid:{id}")
    table_name("widgets")

    attribute_mappings([
      {:label, "https://schema.org/name"}
    ])
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:label]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :label, :string, allow_nil?: false, public?: true
  end
end
```

## Inspect the mapping

`AshR2RML.Resource.Info.mapping_result/1` compiles the resource into the mapping IR, or
returns a typed `AshR2RML.Refusal`.

```elixir
{:ok, %AshR2RML.Mapping.Resource{} = mapping} =
  AshR2RML.Resource.Info.mapping_result(MyApp.Widget)

mapping.logical_table.table_name
#=> "widgets"
mapping.subject_map.value
#=> "urn:uuid:{id}"
```

## Render Turtle

`AshR2RML.R2RML.render/1` accepts a resource module, a list of modules, a mapping
`Resource`, or a `Bundle`.

```elixir
{:ok, ttl} = AshR2RML.R2RML.render(MyApp.Widget)

ttl =~ ~s(rr:tableName "widgets")
#=> true
ttl =~ "rr:class <https://schema.org/Thing>"
#=> true
ttl =~ "rr:predicate <https://schema.org/name>"
#=> true
```

## Query in memory

`AshR2RML.OBDA.InMemory.query/4` reads real rows through Ash, materializes an RDF graph
from the mapping, and runs SPARQL over it. Options such as `domain:`, `actor:` and
`tenant:` are forwarded to the Ash read.

```elixir
widget =
  MyApp.Widget
  |> Ash.Changeset.for_create(:create, %{label: "gear"}, domain: MyApp.Domain)
  |> Ash.create!(domain: MyApp.Domain)

{:ok, observation} =
  AshR2RML.OBDA.InMemory.query(
    MyApp.Widget,
    mapping,
    "SELECT ?s ?l WHERE { ?s a <https://schema.org/Thing> ; " <>
      "<https://schema.org/name> ?l . }",
    domain: MyApp.Domain
  )

observation.rows
#=> [%{"s" => "urn:uuid:#{widget.id}", "l" => "gear"}]
```

### Actor and tenant

For a resource with policies, pass `actor:`; rows the actor may not read never enter the
graph. For an attribute-multitenant resource, pass `tenant:`.

```elixir
@select "SELECT ?s ?t WHERE { ?s <https://schema.org/headline> ?t }"

AshR2RML.OBDA.InMemory.query(Note, note_mapping, @select,
  domain: Domain,
  actor: %{name: "alice"}
)

AshR2RML.OBDA.InMemory.query(TenantNote, tenant_mapping, @select,
  domain: Domain,
  tenant: "A"
)
```

`Note` (policy `authorize_if expr(owner == ^actor(:name))`) and `TenantNote`
(`multitenancy do strategy :attribute; attribute :tenant_id end`) are defined in
`test/obda_in_memory_row_policy_tenant_test.exs`.

## Round-trip an IRI

`AshR2RML.Subject` is pure: it converts key values to the subject IRI and back using the
mapping's subject template. Values are percent-encoded; `from_iri/2` refuses any IRI that
does not re-encode exactly.

```elixir
{:ok, iri} = AshR2RML.Subject.to_iri(MyApp.Widget, %{id: "a b"})
#=> {:ok, "urn:uuid:a%20b"}

AshR2RML.Subject.from_iri(MyApp.Widget, iri)
#=> {:ok, %{id: "a b"}}

AshR2RML.Subject.from_iri(MyApp.Widget, "urn:sha256:00")
#=> {:error, %AshR2RML.Refusal{code: :REFUSED_INVALID_TERM_MAP}}
```

The first argument may also be a `%AshR2RML.Mapping.Resource{}`.

## See Also

- `documentation/reference/dsl_cheatsheet.md`
- `AGENTS.md` for the refusal vocabulary
