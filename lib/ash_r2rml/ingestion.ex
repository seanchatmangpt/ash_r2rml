# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Ingestion do
  @moduledoc """
  RDF/Turtle + SHACL ingestion adapter for the ontology-first compiler.

  The adapter parses a real RDF graph with RDF.ex, extracts closed SHACL node
  and property shapes, and manufactures the normalized application-profile map
  consumed by `AshR2RML.Admission`. It deliberately does not reason over arbitrary
  OWL. Missing closure information is returned as a typed refusal.

  Ash-specific relational hints live in the neutral AshR2RML vocabulary:
  `https://seanchatmangpt.github.io/ash_r2rml#`.
  """

  alias AshR2RML.Refusal

  @rdf_type "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
  @sh "http://www.w3.org/ns/shacl#"
  @r2ml "https://seanchatmangpt.github.io/ash_r2rml#"

  @spec from_turtle(String.t(), keyword()) :: {:ok, map()} | {:error, [Refusal.t()]}
  def from_turtle(turtle, opts \\ []) when is_binary(turtle) and is_list(opts) do
    case RDF.Turtle.read_string(turtle) do
      {:ok, graph} -> from_graph(graph, Keyword.put_new(opts, :source_sha256, sha256(turtle)))
      {:error, reason} -> {:error, [parse_refusal(reason)]}
    end
  rescue
    exception -> {:error, [parse_refusal(Exception.message(exception))]}
  end

  @spec from_graph(RDF.Data.Source.t(), keyword()) :: {:ok, map()} | {:error, [Refusal.t()]}
  def from_graph(graph, opts \\ []) when is_list(opts) do
    statements = RDF.Data.statements(graph)
    index = index_statements(statements)

    shapes =
      statements
      |> Enum.flat_map(fn
        {subject, predicate, object} ->
          if iri_string(predicate) == @rdf_type and iri_string(object) == @sh <> "NodeShape",
            do: [subject],
            else: []

        {subject, predicate, object, _graph_name} ->
          if iri_string(predicate) == @rdf_type and iri_string(object) == @sh <> "NodeShape",
            do: [subject],
            else: []
      end)
      |> Enum.uniq()
      |> Enum.sort_by(&term_sort_key/1)

    if shapes == [] do
      {:error,
       [
         Refusal.new(
           :REFUSED_SHACL_PROFILE_INCOMPLETE,
           :profile,
           "RDF graph contains no sh:NodeShape subjects"
         )
       ]}
    else
      case parse_resources(shapes, index) do
        {:error, refusals} ->
          {:error, List.wrap(refusals)}

        {:ok, resources} ->
          canonical_resources = Enum.sort_by(resources, & &1.class_iri)
          profile_hash = sha256(canonical_binary(canonical_resources))

          {:ok,
           %{
             ontology_hash: Keyword.get(opts, :ontology_hash),
             profile_hash: profile_hash,
             shacl_hash: Keyword.get(opts, :shacl_hash, Keyword.get(opts, :source_sha256)),
             resources: canonical_resources
           }}
      end
    end
  rescue
    exception ->
      {:error,
       [
         Refusal.new(
           :REFUSED_RDF_PARSE,
           :profile,
           "failed to inspect RDF graph",
           %{reason: Exception.message(exception)}
         )
       ]}
  end

  @spec compile_turtle(String.t(), keyword()) ::
          {:ok, AshR2RML.Compilation.t()} | {:error, AshR2RML.Compilation.t() | [Refusal.t()]}
  def compile_turtle(turtle, opts \\ []) do
    with {:ok, profile} <- from_turtle(turtle, opts),
         {:ok, compilation} <- AshR2RML.Compiler.compile(profile) do
      {:ok, compilation.mapping_bundle}
    end
  end

  defp parse_resources(shapes, index) do
    Enum.reduce_while(shapes, {:ok, []}, fn shape, {:ok, acc} ->
      case parse_resource(shape, index) do
        {:ok, resource} -> {:cont, {:ok, [resource | acc]}}
        {:error, refusal} -> {:halt, {:error, [refusal]}}
      end
    end)
    |> case do
      {:ok, resources} -> {:ok, Enum.reverse(resources)}
      other -> other
    end
  end

  defp parse_resource(shape, index) do
    with {:ok, shape_iri} <- require_iri_term(shape, :shape),
         {:ok, class_iri} <- required_iri(index, shape, @sh <> "targetClass", shape_iri),
         {:ok, module_name} <- required_literal(index, shape, @r2ml <> "ashModule", shape_iri),
         {:ok, table_name} <- required_literal(index, shape, @r2ml <> "tableName", shape_iri),
         {:ok, subject_template} <-
           required_literal(index, shape, @r2ml <> "subjectTemplate", shape_iri),
         {:ok, identities} <- parse_identities(index, shape, shape_iri),
         {:ok, parsed_properties} <- parse_properties(index, shape, class_iri, shape_iri) do
      {attributes, relationships} = Enum.split_with(parsed_properties, &match?({:attribute, _}, &1))

      attributes =
        attributes
        |> Enum.map(&elem(&1, 1))
        |> Enum.sort_by(&to_string(&1.name))

      relationships =
        relationships
        |> Enum.map(&elem(&1, 1))
        |> Enum.sort_by(&to_string(&1.name))

      {:ok,
       %{
         iri: optional_iri(index, shape, @r2ml <> "resourceIri") || class_iri,
         class_iri: class_iri,
         shape_iri: shape_iri,
         module: module_name,
         repo_module: optional_literal(index, shape, @r2ml <> "repoModule"),
         table: table_name,
         subject_template: subject_template,
         identities: identities,
         attributes: attributes,
         relationships: relationships,
         provenance: %{
           ingestion: :rdf_shacl,
           shape_iri: shape_iri
         }
       }}
    end
  end

  defp parse_identities(index, shape, shape_iri) do
    identity_nodes = objects(index, shape, @r2ml <> "identity")

    if identity_nodes == [] do
      {:error,
       Refusal.new(
         :REFUSED_NON_UNIQUE_SEMANTIC_IDENTITY,
         shape_iri,
         "closed SHACL profile must declare at least one r2ml:identity"
       )}
    else
      identity_nodes
      |> Enum.sort_by(&term_sort_key/1)
      |> Enum.reduce_while({:ok, []}, fn identity_node, {:ok, acc} ->
        with {:ok, name_string} <-
               required_literal(index, identity_node, @r2ml <> "identityName", shape_iri),
             {:ok, name} <- safe_atom(name_string, shape_iri),
             {:ok, keys} <- identity_keys(index, identity_node, shape_iri) do
          identity = %{
            name: name,
            keys: keys,
            primary?: optional_boolean(index, identity_node, @r2ml <> "primaryIdentity", false),
            template: optional_literal(index, identity_node, @r2ml <> "identityTemplate")
          }

          {:cont, {:ok, [identity | acc]}}
        else
          {:error, refusal} -> {:halt, {:error, refusal}}
        end
      end)
      |> case do
        {:ok, identities} -> {:ok, Enum.reverse(identities)}
        other -> other
      end
    end
  end

  defp identity_keys(index, identity_node, subject) do
    values =
      objects(index, identity_node, @r2ml <> "identityKey")
      |> Enum.map(&literal_value/1)

    cond do
      values == [] ->
        {:error,
         Refusal.new(
           :REFUSED_NON_UNIQUE_SEMANTIC_IDENTITY,
           subject,
           "r2ml:identity requires at least one r2ml:identityKey"
         )}

      Enum.any?(values, &is_nil/1) ->
        {:error,
         Refusal.new(
           :REFUSED_NON_UNIQUE_SEMANTIC_IDENTITY,
           subject,
           "identity keys must be RDF literals naming Ash attributes"
         )}

      true ->
        values
        |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
          case safe_atom(to_string(value), subject) do
            {:ok, key} -> {:cont, {:ok, [key | acc]}}
            {:error, refusal} -> {:halt, {:error, refusal}}
          end
        end)
        |> case do
          {:ok, keys} -> {:ok, Enum.reverse(keys)}
          other -> other
        end
    end
  end

  defp parse_properties(index, shape, source_class, shape_iri) do
    objects(index, shape, @sh <> "property")
    |> Enum.sort_by(&term_sort_key/1)
    |> Enum.reduce_while({:ok, []}, fn property_shape, {:ok, acc} ->
      case parse_property(index, property_shape, source_class, shape_iri) do
        {:ok, property} -> {:cont, {:ok, [property | acc]}}
        {:error, refusal} -> {:halt, {:error, refusal}}
      end
    end)
    |> case do
      {:ok, properties} -> {:ok, Enum.reverse(properties)}
      other -> other
    end
  end

  defp parse_property(index, property_shape, source_class, shape_iri) do
    with {:ok, predicate_iri} <- required_iri(index, property_shape, @sh <> "path", shape_iri),
         {:ok, name_string} <-
           required_literal(index, property_shape, @r2ml <> "ashName", predicate_iri),
         {:ok, name} <- safe_atom(name_string, predicate_iri) do
      datatype_iri = optional_iri(index, property_shape, @sh <> "datatype")
      target_class = optional_iri(index, property_shape, @sh <> "class")
      min_count = optional_integer(index, property_shape, @sh <> "minCount", 0)
      max_count = optional_integer(index, property_shape, @sh <> "maxCount", nil)

      cond do
        datatype_iri && target_class ->
          {:error,
           Refusal.new(
             :REFUSED_SHACL_PROFILE_INCOMPLETE,
             predicate_iri,
             "property shape cannot be both sh:datatype and sh:class"
           )}

        datatype_iri ->
          {:ok,
           {:attribute,
            %{
              name: name,
              column: optional_literal(index, property_shape, @r2ml <> "columnName") || name_string,
              predicate_iri: predicate_iri,
              datatype_iri: datatype_iri,
              ash_type: optional_ash_type(index, property_shape),
              postgres_type: optional_literal(index, property_shape, @r2ml <> "postgresType"),
              min_count: min_count,
              max_count: max_count,
              nullable: min_count == 0,
              identity?: optional_boolean(index, property_shape, @r2ml <> "identityKey", false),
              provenance: %{property_shape: term_sort_key(property_shape)}
            }}}

        target_class ->
          {:ok,
           {:relationship,
            %{
              name: name,
              predicate_iri: predicate_iri,
              inverse_predicate: optional_iri(index, property_shape, @r2ml <> "inversePredicate"),
              source_class: source_class,
              target_class: target_class,
              min_count: min_count,
              max_count: max_count,
              storage_strategy: optional_storage_strategy(index, property_shape, @r2ml <> "storageStrategy"),
              source_key: optional_atom(index, property_shape, @r2ml <> "sourceKey", predicate_iri),
              destination_key: optional_atom(index, property_shape, @r2ml <> "destinationKey", predicate_iri),
              join_table: optional_literal(index, property_shape, @r2ml <> "joinTable"),
              source_join_column: optional_literal(index, property_shape, @r2ml <> "sourceJoinColumn"),
              destination_join_column: optional_literal(index, property_shape, @r2ml <> "destinationJoinColumn"),
              association_resource: optional_literal(index, property_shape, @r2ml <> "associationResource"),
              properties: [],
              provenance: %{property_shape: term_sort_key(property_shape)}
            }}}

        true ->
          {:error,
           Refusal.new(
             :REFUSED_SHACL_PROFILE_INCOMPLETE,
             predicate_iri,
             "property shape must close value semantics with sh:datatype or sh:class"
           )}
      end
    end
  end

  defp index_statements(statements) do
    Enum.reduce(statements, %{}, fn
      {subject, predicate, object}, acc -> put_object(acc, subject, predicate, object)
      {subject, predicate, object, _graph_name}, acc -> put_object(acc, subject, predicate, object)
    end)
  end

  defp put_object(acc, subject, predicate, object) do
    predicate = iri_string(predicate)
    update_in(acc, [Access.key(subject, %{}), Access.key(predicate, [])], &(&1 ++ [object]))
  end

  defp objects(index, subject, predicate), do: get_in(index, [subject, predicate]) || []

  defp required_iri(index, subject, predicate, refusal_subject) do
    case objects(index, subject, predicate) do
      [object] ->
        require_iri_term(object, refusal_subject)

      values ->
        {:error,
         Refusal.new(
           :REFUSED_SHACL_PROFILE_INCOMPLETE,
           refusal_subject,
           "expected exactly one #{predicate}",
           %{count: length(values)}
         )}
    end
  end

  defp optional_iri(index, subject, predicate) do
    case objects(index, subject, predicate) do
      [object] -> iri_string(object)
      _ -> nil
    end
  end

  defp require_iri_term(term, subject) do
    case iri_string(term) do
      nil ->
        {:error,
         Refusal.new(
           :REFUSED_UNSUPPORTED_SHACL_PATH,
           subject,
           "expected an absolute RDF IRI; complex/blank-node SHACL paths are not admitted"
         )}

      iri ->
        {:ok, iri}
    end
  end

  defp required_literal(index, subject, predicate, refusal_subject) do
    case objects(index, subject, predicate) do
      [object] ->
        case literal_value(object) do
          nil ->
            {:error,
             Refusal.new(
               :REFUSED_SHACL_PROFILE_INCOMPLETE,
               refusal_subject,
               "#{predicate} must be an RDF literal"
             )}

          value ->
            {:ok, to_string(value)}
        end

      values ->
        {:error,
         Refusal.new(
           :REFUSED_SHACL_PROFILE_INCOMPLETE,
           refusal_subject,
           "expected exactly one #{predicate}",
           %{count: length(values)}
         )}
    end
  end

  defp optional_literal(index, subject, predicate) do
    case objects(index, subject, predicate) do
      [object] -> object |> literal_value() |> maybe_to_string()
      _ -> nil
    end
  end

  defp optional_boolean(index, subject, predicate, default) do
    case objects(index, subject, predicate) do
      [object] ->
        case literal_value(object) do
          value when is_boolean(value) -> value
          "true" -> true
          "false" -> false
          _ -> default
        end

      _ ->
        default
    end
  end

  defp optional_integer(index, subject, predicate, default) do
    case objects(index, subject, predicate) do
      [object] ->
        case literal_value(object) do
          value when is_integer(value) ->
            value

          value when is_binary(value) ->
            case Integer.parse(value) do
              {integer, ""} -> integer
              _ -> default
            end

          _ ->
            default
        end

      _ ->
        default
    end
  end

  defp optional_atom(index, subject, predicate, refusal_subject) do
    case optional_literal(index, subject, predicate) do
      nil ->
        nil

      value ->
        case safe_atom(value, refusal_subject) do
          {:ok, atom} -> atom
          {:error, _} -> nil
        end
    end
  end

  defp optional_ash_type(index, property_shape) do
    case optional_literal(index, property_shape, @r2ml <> "ashType") do
      nil -> nil
      "string" -> :string
      "boolean" -> :boolean
      "integer" -> :integer
      "float" -> :float
      "decimal" -> :decimal
      "date" -> :date
      "utc_datetime" -> :utc_datetime
      "utc_datetime_usec" -> :utc_datetime_usec
      "uuid" -> :uuid
      module_name when is_binary(module_name) -> Module.concat(String.split(module_name, ".", trim: true))
    end
  end

  defp optional_storage_strategy(index, subject, predicate) do
    case optional_literal(index, subject, predicate) do
      "foreign_key" -> :foreign_key
      "join_table" -> :join_table
      "association_resource" -> :association_resource
      "array" -> :array
      "jsonb" -> :jsonb
      "computed_projection" -> :computed_projection
      nil -> nil
      other -> other
    end
  end

  defp safe_atom(value, subject) when is_binary(value) do
    if byte_size(value) <= 128 and Regex.match?(~r/^[a-z_][a-zA-Z0-9_]*$/, value) do
      {:ok, String.to_atom(value)}
    else
      {:error,
       Refusal.new(
         :REFUSED_SHACL_PROFILE_INCOMPLETE,
         subject,
         "Ash names/identity keys must be bounded identifier literals",
         %{value: value}
       )}
    end
  end

  defp iri_string(%RDF.IRI{} = iri), do: RDF.IRI.to_string(iri)
  defp iri_string(_), do: nil

  defp literal_value(%RDF.Literal{} = literal), do: RDF.Literal.value(literal)
  defp literal_value(_), do: nil

  defp maybe_to_string(nil), do: nil
  defp maybe_to_string(value), do: to_string(value)

  defp term_sort_key(%RDF.IRI{} = iri), do: RDF.IRI.to_string(iri)
  defp term_sort_key(%RDF.BlankNode{} = bnode), do: "_:" <> to_string(RDF.BlankNode.value(bnode))
  defp term_sort_key(term), do: inspect(term)

  defp parse_refusal(reason) do
    Refusal.new(
      :REFUSED_RDF_PARSE,
      :turtle,
      "RDF/Turtle could not be parsed",
      %{reason: inspect(reason)}
    )
  end

  defp canonical_binary(term) do
    term
    |> canonical_term()
    |> :erlang.term_to_binary([:deterministic])
  end

  defp canonical_term(%_{} = struct), do: struct |> Map.from_struct() |> canonical_term()

  defp canonical_term(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> {key, canonical_term(value)} end)
    |> Enum.sort_by(fn {key, _value} -> inspect(key) end)
  end

  defp canonical_term(list) when is_list(list), do: Enum.map(list, &canonical_term/1)
  defp canonical_term(other), do: other

  defp sha256(value) when is_binary(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
end
