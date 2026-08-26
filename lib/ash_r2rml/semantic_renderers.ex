# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Semantic.Ash do
  @moduledoc "Manufactures Ash resource source from the admitted semantic IR."

  alias AshR2RML.SemanticIR.{Relationship, Resource}

  @doc """
  Renders Ash resource source from `ir`.

  `opts` is additive and defaults to producing byte-identical output to before
  it existed: `graphql: true` and/or `json_api: true` add `AshGraphql.Resource`/
  `AshJsonApi.Resource` to every resource's `extensions:` list and a minimal,
  real `graphql do type ... end` / `json_api do type ... end` block per
  resource, with the type name auto-derived from the same mapping IR that
  already drives `r2rml`'s `class_iri`/`attribute_mappings` -- no hand-written
  GraphQL/JSON:API wiring, no new runtime dependency on `ash_graphql`/
  `ash_json_api` for AshR2RML itself (they are `:test`-only, used here solely
  to verify the emitted source actually compiles as a real Ash resource).

  This does not "add support" for GraphQL/JSON:API -- any consumer resource
  can already add those extensions directly, independent of AshR2RML, because
  Ash extensions compose. This only auto-derives the minimal starting block
  from the mapping so a resource author doesn't have to invent the type name
  by hand.
  """
  @spec render(AshR2RML.SemanticIR.t(), keyword()) :: {:ok, String.t()}
  def render(ir, opts \\ [])

  def render(%AshR2RML.SemanticIR{resources: resources}, opts) do
    resources = Enum.sort_by(resources, &module_name(&1.module))

    association_modules =
      resources
      |> Enum.flat_map(fn resource ->
        Enum.flat_map(resource.relationships, fn
          %Relationship{storage_strategy: :join_table} = relationship ->
            [render_join_resource(resource, relationship, resources)]

          _ ->
            []
        end)
      end)

    {:ok,
     Enum.map_join(resources, "\n\n", &render_resource(&1, resources, opts)) <>
       join_generated(association_modules)}
  end

  defp render_resource(resource, resources, opts) do
    attributes = Enum.map_join(resource.attributes, "\n", &render_attribute(resource, &1))

    relationships =
      Enum.map_join(resource.relationships, "\n", &render_relationship(resource, &1, resources))

    identities =
      resource.identities
      |> Enum.reject(& &1.primary?)
      |> Enum.map_join("\n", &render_identity/1)

    repo = if resource.repo_module, do: "    repo #{module_name(resource.repo_module)}\n", else: ""
    data_layer = if resource.repo_module, do: "AshPostgres.DataLayer", else: "Ash.DataLayer.Ets"

    postgres_block =
      if resource.repo_module do
        """
          postgres do
            table #{inspect(resource.table)}
        #{repo}  end
        """
      else
        ""
      end

    extensions = ["AshR2RML"] ++ api_extension_names(opts)
    api_blocks = render_api_blocks(resource, opts)

    """
    defmodule #{module_name(resource.module)} do
      use Ash.Resource,
        domain: nil,
        data_layer: #{data_layer},
        extensions: [#{Enum.join(extensions, ", ")}]

    #{postgres_block}
    #{api_blocks}

      r2rml do
        class_iri #{inspect(resource.class_iri)}
        subject_template #{inspect(resource.subject_template)}
        table_name #{inspect(resource.table)}
        attribute_mappings #{inspect(untyped_attribute_mappings(resource))}
        typed_attribute_mappings #{inspect(typed_attribute_mappings(resource))}
        relationship_mappings #{inspect(Enum.map(resource.relationships, &{&1.name, &1.predicate_iri}))}
      end

      attributes do
    #{attributes}
      end

    #{identity_block(identities)}#{relationship_block(relationships)}  actions do
        defaults [:read, :create, :update, :destroy]
      end
    end
    """
    |> String.trim()
  end

  defp render_attribute(resource, attribute) do
    primary? = primary_key?(resource, attribute.name)

    options =
      [
        "allow_nil?: #{inspect(if(primary?, do: false, else: attribute.nullable))}",
        "public?: true",
        if(primary?, do: "primary_key?: true", else: nil),
        if(attribute.column != to_string(attribute.name),
          do: "source: #{inspect(String.to_atom(attribute.column))}",
          else: nil
        )
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(", ")

    "    attribute #{inspect(attribute.name)}, #{ash_type(attribute.ash_type)}, #{options}"
  end

  defp render_identity(identity), do: "    identity #{inspect(identity.name)}, #{inspect(identity.keys)}"

  defp identity_block(""), do: ""
  defp identity_block(body), do: "  identities do\n#{body}\n  end\n\n"

  defp relationship_block(""), do: ""
  defp relationship_block(body), do: "  relationships do\n#{body}\n  end\n\n"

  defp render_relationship(_resource, %Relationship{storage_strategy: nil}, _resources), do: ""

  defp render_relationship(_resource, %Relationship{storage_strategy: :foreign_key} = rel, resources) do
    destination = resource_by_class!(resources, rel.target_class)
    nullable = rel.min_count == 0

    """
        belongs_to #{inspect(rel.name)}, #{module_name(destination.module)} do
          source_attribute #{inspect(rel.source_key)}
          destination_attribute #{inspect(rel.destination_key)}
          define_attribute? false
          allow_nil? #{inspect(nullable)}
          public? true
        end
    """
    |> String.trim_trailing()
  end

  defp render_relationship(resource, %Relationship{storage_strategy: :join_table} = rel, resources) do
    destination = resource_by_class!(resources, rel.target_class)
    through = association_module(resource, rel, destination)

    """
        many_to_many #{inspect(rel.name)}, #{module_name(destination.module)} do
          through #{through}
          source_attribute #{inspect(rel.source_key)}
          destination_attribute #{inspect(rel.destination_key)}
          source_attribute_on_join_resource #{inspect(String.to_atom(rel.source_join_column))}
          destination_attribute_on_join_resource #{inspect(String.to_atom(rel.destination_join_column))}
          public? true
        end
    """
    |> String.trim_trailing()
  end

  defp render_relationship(_resource, %Relationship{storage_strategy: :association_resource}, _resources),
    do: ""

  defp render_join_resource(resource, rel, resources) do
    destination = resource_by_class!(resources, rel.target_class)
    source_attr = attribute!(resource, rel.source_key)
    destination_attr = attribute!(destination, rel.destination_key)
    module = association_module(resource, rel, destination)
    repo = if resource.repo_module, do: "    repo #{module_name(resource.repo_module)}\n", else: ""

    """
    defmodule #{module} do
      use Ash.Resource, data_layer: AshPostgres.DataLayer

      postgres do
        table #{inspect(rel.join_table)}
    #{repo}  end

      attributes do
        attribute #{inspect(String.to_atom(rel.source_join_column))}, #{ash_type(source_attr.ash_type)}, allow_nil?: false, primary_key?: true
        attribute #{inspect(String.to_atom(rel.destination_join_column))}, #{ash_type(destination_attr.ash_type)}, allow_nil?: false, primary_key?: true
      end

      relationships do
        belongs_to :source, #{module_name(resource.module)}, source_attribute: #{inspect(String.to_atom(rel.source_join_column))}, destination_attribute: #{inspect(rel.source_key)}, define_attribute?: false
        belongs_to :destination, #{module_name(destination.module)}, source_attribute: #{inspect(String.to_atom(rel.destination_join_column))}, destination_attribute: #{inspect(rel.destination_key)}, define_attribute?: false
      end

      actions do
        defaults [:read, :create, :destroy]
      end
    end
    """
    |> String.trim()
  end

  # Derives a minimal, real, compilable `graphql do ... end` / `json_api do ... end` block per
  # opted-in API kind. The type name is auto-derived from the resource's own module name (the
  # same identity `class_iri`/`table` already come from) rather than invented separately --
  # deliberately minimal (just `type`, which both extensions accept as sufficient to expose
  # every public attribute) rather than an exhaustive field-by-field mirror of `attribute_mappings`,
  # since the real DSL surface for field-level GraphQL/JSON:API customization is broader than
  # this mapping IR models and is left for the resource author to extend by hand from here.
  defp api_extension_names(opts) do
    [
      if(Keyword.get(opts, :graphql, false), do: "AshGraphql.Resource"),
      if(Keyword.get(opts, :json_api, false), do: "AshJsonApi.Resource")
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp render_api_blocks(resource, opts) do
    type_name = api_type_name(resource)

    graphql_block =
      if Keyword.get(opts, :graphql, false) do
        """
          graphql do
            type #{inspect(type_name)}
          end

        """
      else
        ""
      end

    json_api_block =
      if Keyword.get(opts, :json_api, false) do
        """
          json_api do
            type #{inspect(to_string(type_name))}
          end

        """
      else
        ""
      end

    graphql_block <> json_api_block
  end

  defp api_type_name(resource) do
    resource.module
    |> module_name()
    |> String.split(".")
    |> List.last()
    |> Macro.underscore()
    |> String.to_atom()
  end

  defp primary_key?(resource, attribute_name) do
    case Enum.find(resource.identities, & &1.primary?) do
      nil -> false
      identity -> attribute_name in identity.keys
    end
  end

  defp untyped_attribute_mappings(resource) do
    for attribute <- resource.attributes,
        is_nil(attribute.datatype_iri),
        do: {attribute.name, attribute.predicate_iri}
  end

  defp typed_attribute_mappings(resource) do
    for attribute <- resource.attributes,
        not is_nil(attribute.datatype_iri),
        do: {attribute.name, attribute.predicate_iri, attribute.datatype_iri}
  end

  defp association_module(_resource, %{association_resource: explicit}, _destination)
       when not is_nil(explicit),
       do: module_name(explicit)

  defp association_module(resource, rel, destination) do
    source_parts = module_parts(resource.module)
    namespace = Enum.drop(source_parts, -1)
    source = List.last(source_parts)
    target = destination.module |> module_parts() |> List.last()
    Enum.join(namespace ++ [source <> target <> Macro.camelize(to_string(rel.name)) <> "Link"], ".")
  end

  defp resource_by_class!(resources, class_iri), do: Enum.find(resources, &(&1.class_iri == class_iri))
  defp attribute!(%Resource{} = resource, name), do: Enum.find(resource.attributes, &(&1.name == name))

  defp module_parts(module) when is_atom(module), do: Module.split(module)
  defp module_parts(module) when is_binary(module), do: String.split(module, ".", trim: true)
  defp module_name(module) when is_atom(module), do: inspect(module)
  defp module_name(module) when is_binary(module), do: module

  defp ash_type(type)
       when is_atom(type) and
              type in [:string, :boolean, :integer, :float, :decimal, :date, :utc_datetime, :utc_datetime_usec, :uuid],
       do: inspect(type)

  defp ash_type(type) when is_atom(type), do: inspect(type)
  defp ash_type(type), do: inspect(type)

  defp join_generated([]), do: ""
  defp join_generated(modules), do: "\n\n" <> Enum.join(modules, "\n\n")
end

defmodule AshR2RML.Semantic.SQL do
  @moduledoc """
  Manufactures deterministic PostgreSQL DDL from the admitted semantic IR.

  Base tables are created before any inter-table foreign-key constraint. This
  makes the projection independent of lexical resource ordering and supports
  mutually-referencing resource topologies without requiring a hidden ordering
  heuristic.
  """

  alias AshR2RML.SemanticIR.Relationship

  def render(%AshR2RML.SemanticIR{resources: resources}) do
    resources = Enum.sort_by(resources, & &1.table)
    tables = Enum.map(resources, &render_table/1)
    foreign_keys = Enum.flat_map(resources, &render_foreign_keys(&1, resources))
    joins = Enum.flat_map(resources, &render_join_tables(&1, resources))
    {:ok, Enum.join(tables ++ foreign_keys ++ joins, "\n\n") <> "\n"}
  end

  defp render_table(resource) do
    definitions = Enum.map(resource.attributes, &column_definition/1) ++ identity_constraints(resource)

    "CREATE TABLE IF NOT EXISTS #{quote_ident(resource.table)} (\n" <>
      Enum.map_join(definitions, ",\n", &"  #{&1}") <>
      "\n);"
  end

  defp column_definition(attribute) do
    nullability = if attribute.nullable, do: "", else: " NOT NULL"
    "#{quote_ident(attribute.column)} #{attribute.postgres_type}#{nullability}"
  end

  defp identity_constraints(resource) do
    Enum.map(resource.identities, fn identity ->
      columns =
        identity.keys
        |> Enum.map(&attribute_column!(resource, &1))
        |> Enum.map_join(", ", &quote_ident/1)

      kind = if identity.primary?, do: "PRIMARY KEY", else: "UNIQUE"

      "CONSTRAINT #{quote_ident(resource.table <> "_" <> to_string(identity.name))} #{kind} (#{columns})"
    end)
  end

  defp render_foreign_keys(resource, resources) do
    for %Relationship{storage_strategy: :foreign_key} = rel <- resource.relationships do
      destination = Enum.find(resources, &(&1.class_iri == rel.target_class))
      child = attribute_column!(resource, rel.source_key)
      parent = attribute_column!(destination, rel.destination_key)
      constraint = resource.table <> "_" <> to_string(rel.name) <> "_fk"

      "ALTER TABLE #{quote_ident(resource.table)}\n" <>
        "  ADD CONSTRAINT #{quote_ident(constraint)} FOREIGN KEY (#{quote_ident(child)}) " <>
        "REFERENCES #{quote_ident(destination.table)} (#{quote_ident(parent)});"
    end
  end

  defp render_join_tables(resource, resources) do
    for %Relationship{storage_strategy: :join_table} = rel <- resource.relationships do
      destination = Enum.find(resources, &(&1.class_iri == rel.target_class))
      source_attr = Enum.find(resource.attributes, &(&1.name == rel.source_key))
      destination_attr = Enum.find(destination.attributes, &(&1.name == rel.destination_key))

      """
      CREATE TABLE IF NOT EXISTS #{quote_ident(rel.join_table)} (
        #{quote_ident(rel.source_join_column)} #{source_attr.postgres_type} NOT NULL,
        #{quote_ident(rel.destination_join_column)} #{destination_attr.postgres_type} NOT NULL,
        PRIMARY KEY (#{quote_ident(rel.source_join_column)}, #{quote_ident(rel.destination_join_column)}),
        FOREIGN KEY (#{quote_ident(rel.source_join_column)}) REFERENCES #{quote_ident(resource.table)} (#{quote_ident(source_attr.column)}),
        FOREIGN KEY (#{quote_ident(rel.destination_join_column)}) REFERENCES #{quote_ident(destination.table)} (#{quote_ident(destination_attr.column)})
      );
      """
      |> String.trim()
    end
  end

  defp attribute_column!(resource, key), do: Enum.find(resource.attributes, &(&1.name == key)).column
  defp quote_ident(value), do: "\"" <> String.replace(to_string(value), "\"", "\"\"") <> "\""
end

defmodule AshR2RML.Semantic.R2RML do
  @moduledoc "R2RML renderer whose sole source is the ontology-first semantic IR."

  alias AshR2RML.SemanticIR.Relationship

  @prefixes """
  @prefix rr: <http://www.w3.org/ns/r2rml#> .
  @prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .
  @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

  """

  def render(%AshR2RML.SemanticIR{resources: resources}) do
    resources = Enum.sort_by(resources, & &1.class_iri)
    maps = Enum.map(resources, &render_resource(&1, resources))
    join_maps = Enum.flat_map(resources, &render_join_maps(&1, resources))
    {:ok, @prefixes <> Enum.join(maps ++ join_maps, "\n")}
  end

  defp render_resource(resource, resources) do
    attrs = Enum.map(resource.attributes, &render_attribute/1)

    relationships =
      resource.relationships
      |> Enum.filter(&(&1.storage_strategy == :foreign_key))
      |> Enum.map(&render_fk_relationship(resource, &1, resources))

    suffix = predicate_suffix(attrs ++ relationships)

    "<##{map_id(resource)}> a rr:TriplesMap ;\n" <>
      "  rr:logicalTable [ rr:tableName #{literal(resource.table)} ] ;\n" <>
      "  rr:subjectMap [ rr:template #{literal(resource.subject_template)}; rr:class <#{resource.class_iri}> ]#{suffix} .\n"
  end

  defp render_attribute(attribute) do
    datatype =
      if attribute.datatype_iri,
        do: "; rr:datatype <#{attribute.datatype_iri}>",
        else: ""

    "  rr:predicateObjectMap [ rr:predicate <#{attribute.predicate_iri}>; " <>
      "rr:objectMap [ rr:column #{literal(attribute.column)}#{datatype} ] ]"
  end

  defp render_fk_relationship(resource, relationship, resources) do
    destination = Enum.find(resources, &(&1.class_iri == relationship.target_class))
    child = Enum.find(resource.attributes, &(&1.name == relationship.source_key)).column
    parent = Enum.find(destination.attributes, &(&1.name == relationship.destination_key)).column

    "  rr:predicateObjectMap [ rr:predicate <#{relationship.predicate_iri}>; " <>
      "rr:objectMap [ rr:parentTriplesMap <##{map_id(destination)}>; " <>
      "rr:joinCondition [ rr:child #{literal(child)}; rr:parent #{literal(parent)} ] ] ]"
  end

  defp render_join_maps(resource, resources) do
    for %Relationship{storage_strategy: :join_table} = rel <- resource.relationships do
      destination = Enum.find(resources, &(&1.class_iri == rel.target_class))
      source_attr = Enum.find(resource.attributes, &(&1.name == rel.source_key))
      destination_attr = Enum.find(destination.attributes, &(&1.name == rel.destination_key))
      template = remap_template(resource.subject_template, source_attr.column, rel.source_join_column)
      id = map_id(resource) <> "_" <> Macro.camelize(to_string(rel.name))

      "<##{id}> a rr:TriplesMap ;\n" <>
        "  rr:logicalTable [ rr:tableName #{literal(rel.join_table)} ] ;\n" <>
        "  rr:subjectMap [ rr:template #{literal(template)} ] ;\n" <>
        "  rr:predicateObjectMap [ rr:predicate <#{rel.predicate_iri}>; " <>
        "rr:objectMap [ rr:parentTriplesMap <##{map_id(destination)}>; " <>
        "rr:joinCondition [ rr:child #{literal(rel.destination_join_column)}; " <>
        "rr:parent #{literal(destination_attr.column)} ] ] ] .\n"
    end
  end

  defp remap_template(template, source_column, join_column),
    do: String.replace(template, "{#{source_column}}", "{#{join_column}}")

  defp predicate_suffix([]), do: ""
  defp predicate_suffix(values), do: ";\n" <> Enum.join(values, ";\n")
  defp map_id(resource), do: resource.module |> module_parts() |> Enum.join("_")
  defp module_parts(module) when is_atom(module), do: Module.split(module)
  defp module_parts(module) when is_binary(module), do: String.split(module, ".", trim: true)

  defp literal(value) do
    escaped =
      value
      |> to_string()
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")
      |> String.replace("\n", "\\n")

    "\"#{escaped}\""
  end
end

defmodule AshR2RML.Semantic.SHACL do
  @moduledoc "Canonical closed operational SHACL projection from semantic IR."

  def render(%AshR2RML.SemanticIR{resources: resources}) do
    resources = Enum.sort_by(resources, & &1.shape_iri)
    body = Enum.map_join(resources, "\n", &render_resource(&1, resources))

    {:ok,
     "@prefix sh: <http://www.w3.org/ns/shacl#> .\n@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .\n\n" <>
       body}
  end

  defp render_resource(resource, resources) do
    attributes = Enum.map(resource.attributes, &attribute_shape/1)
    relationships = Enum.map(resource.relationships, &relationship_shape(&1, resources))

    suffix =
      if attributes ++ relationships == [],
        do: "",
        else: ";\n" <> Enum.join(attributes ++ relationships, ";\n")

    "<#{resource.shape_iri}> a sh:NodeShape ;\n" <>
      "  sh:targetClass <#{resource.class_iri}>#{suffix} .\n"
  end

  defp attribute_shape(attribute) do
    "  sh:property [ sh:path <#{attribute.predicate_iri}>; " <>
      "sh:datatype <#{attribute.datatype_iri}>; sh:minCount #{attribute.min_count}" <>
      max_count(attribute.max_count) <> " ]"
  end

  defp relationship_shape(relationship, resources) do
    destination = Enum.find(resources, &(&1.class_iri == relationship.target_class))

    "  sh:property [ sh:path <#{relationship.predicate_iri}>; sh:nodeKind sh:IRI; " <>
      "sh:class <#{destination.class_iri}>; sh:minCount #{relationship.min_count}" <>
      max_count(relationship.max_count) <> " ]"
  end

  defp max_count(nil), do: ""
  defp max_count(value), do: "; sh:maxCount #{value}"
end

defmodule AshR2RML.SHACL do
  @moduledoc "SHACL shapes renderer."

  alias AshR2RML.Mapping.Bundle

  def render(%Bundle{} = bundle) do
    by_resource = Map.new(bundle.resources, &{&1.ash_resource, &1})

    shapes =
      Enum.map(bundle.resources, fn resource ->
        props =
          Enum.map(resource.predicate_object_maps, fn pom ->
            datatype = pom.object_map.datatype && pom.object_map.datatype.rdf_datatype
            dt_str = if datatype, do: "; sh:datatype <#{datatype}>", else: ""
            "  sh:property [ sh:path <#{pom.predicate_iri}>#{dt_str}; sh:minCount 1 ]"
          end)

        refs =
          Enum.map(resource.reference_object_maps, fn ref ->
            parent = Map.get(by_resource, ref.parent_resource)
            parent_class = (parent && List.first(parent.class_iris)) || ref.parent_resource
            "  sh:property [ sh:path <#{ref.predicate_iri}>; sh:class <#{parent_class}> ]"
          end)

        body = Enum.join(props ++ refs, " ;\n")
        body_str = if body != "", do: ";\n" <> body, else: ""

        """
        <#{resource.subject_map.value}Shape> a sh:NodeShape ;
          sh:targetClass <#{List.first(resource.class_iris)}>#{body_str} .
        """
      end)

    {:ok,
     "@prefix sh: <http://www.w3.org/ns/shacl#> .\n@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .\n\n" <>
       Enum.join(shapes, "\n")}
  end

  def render(resources) do
    with {:ok, bundle} <- AshR2RML.Compiler.compile_resources(resources) do
      render(bundle)
    end
  end
end
