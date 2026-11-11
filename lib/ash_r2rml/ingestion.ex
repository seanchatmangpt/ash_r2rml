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
      {:ok, graph} -> from_graph(graph, opts)
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
      |> Enum.sort_by(&term_sort_key(&1, index))

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
             shacl_hash:
               Keyword.get(opts, :shacl_hash, Keyword.get(opts, :source_sha256)) || graph_hash(statements, index),
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
         {:ok, parsed_properties} <- parse_properties(index, shape, class_iri, shape_iri),
         {:ok, multitenancy} <- parse_multitenancy(index, shape, shape_iri),
         {:ok, actions} <- parse_actions(index, shape, shape_iri),
         {:ok, policies} <- parse_policies(index, shape, shape_iri),
         {:ok, state_machine} <- parse_state_machine(index, shape, shape_iri) do
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
       }
       |> put_optional(:domain, optional_literal(index, shape, @r2ml <> "domainModule"))
       |> put_optional(:multitenancy, multitenancy)
       |> put_optional(:state_machine, state_machine)
       |> put_optional(:actions, if(actions == [], do: nil, else: actions))
       |> put_optional(:policies, if(policies == [], do: nil, else: policies))}
    end
  end

  # Additive terms are carried only when present so profiles that do not use them keep
  # byte-identical normalized profiles (and therefore identical profile hashes).
  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)

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
      |> Enum.sort_by(&term_sort_key(&1, index))
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
    |> Enum.sort_by(&term_sort_key(&1, index))
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

      with {:ok, enum} <- parse_enum(index, property_shape, predicate_iri) do
        parse_property_kind(
          index,
          property_shape,
          source_class,
          shape_iri,
          predicate_iri,
          name,
          name_string,
          datatype_iri,
          target_class,
          min_count,
          max_count,
          enum
        )
      end
    end
  end

  defp parse_property_kind(
         index,
         property_shape,
         source_class,
         shape_iri,
         predicate_iri,
         name,
         name_string,
         datatype_iri,
         target_class,
         min_count,
         max_count,
         enum
       ) do
    _ = {shape_iri, source_class}

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
            provenance:
              %{property_shape: term_sort_key(property_shape, index)}
              |> put_optional(:enum, enum)
              |> put_optional(
                :generated,
                if(optional_boolean(index, property_shape, @r2ml <> "generated", false), do: true)
              )
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
            provenance: %{property_shape: term_sort_key(property_shape, index)}
          }
          |> put_optional(:inverse_name, optional_literal(index, property_shape, @r2ml <> "inverseName"))}}

      true ->
        {:error,
         Refusal.new(
           :REFUSED_SHACL_PROFILE_INCOMPLETE,
           predicate_iri,
           "property shape must close value semantics with sh:datatype or sh:class"
         )}
    end
  end

  # --- ontology-first extension terms -----------------------------------------------------------

  @rdf_first "http://www.w3.org/1999/02/22-rdf-syntax-ns#first"
  @rdf_rest "http://www.w3.org/1999/02/22-rdf-syntax-ns#rest"
  @rdf_nil "http://www.w3.org/1999/02/22-rdf-syntax-ns#nil"

  defp incomplete(subject, detail, evidence \\ %{}),
    do: {:error, Refusal.new(:REFUSED_SHACL_PROFILE_INCOMPLETE, subject, detail, evidence)}

  defp parse_enum(index, property_shape, subject) do
    case objects(index, property_shape, @sh <> "in") do
      [] ->
        {:ok, nil}

      [head] ->
        with {:ok, items} <- rdf_list(index, head, [], subject),
             {:ok, values} <- enum_values(items, subject) do
          {:ok, %{values: values, module: optional_literal(index, property_shape, @r2ml <> "enumModule")}}
        end

      _ ->
        incomplete(subject, "expected at most one sh:in")
    end
  end

  defp rdf_list(index, node, acc, subject) when length(acc) > 4096,
    do: incomplete(subject, "sh:in list is unbounded", %{node: term_sort_key(node, index)})

  defp rdf_list(index, node, acc, subject) do
    if iri_string(node) == @rdf_nil do
      {:ok, Enum.reverse(acc)}
    else
      case {objects(index, node, @rdf_first), objects(index, node, @rdf_rest)} do
        {[first], [rest]} -> rdf_list(index, rest, [first | acc], subject)
        _ -> incomplete(subject, "sh:in must be a well-formed RDF list")
      end
    end
  end

  defp enum_values(items, subject) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
      with value when is_binary(value) <- literal_value(item),
           {:ok, atom} <- safe_atom(value, subject) do
        {:cont, {:ok, [atom | acc]}}
      else
        _ -> {:halt, incomplete(subject, "sh:in members must be string literals naming bounded identifiers")}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      other -> other
    end
  end

  defp single_node(index, shape, predicate, subject) do
    case objects(index, shape, @r2ml <> predicate) do
      [] -> {:ok, nil}
      [node] -> {:ok, node}
      _ -> incomplete(subject, "expected at most one r2ml:#{predicate}")
    end
  end

  defp parse_multitenancy(index, shape, subject) do
    with {:ok, node} <- single_node(index, shape, "multitenancy", subject) do
      if is_nil(node) do
        {:ok, nil}
      else
        with {:ok, strategy} <- required_literal(index, node, @r2ml <> "tenantStrategy", subject),
             {:ok, strategy} <- tenant_strategy(strategy, subject),
             {:ok, attribute} <- optional_name(index, node, @r2ml <> "tenantAttribute", subject) do
          {:ok,
           %{
             strategy: strategy,
             attribute: attribute,
             global?: optional_boolean(index, node, @r2ml <> "tenantGlobal", false)
           }}
        end
      end
    end
  end

  defp tenant_strategy("attribute", _), do: {:ok, :attribute}
  defp tenant_strategy("context", _), do: {:ok, :context}

  defp tenant_strategy(other, subject),
    do: incomplete(subject, "r2ml:tenantStrategy must be \"attribute\" or \"context\"", %{got: other})

  defp optional_name(index, node, predicate, subject) do
    case optional_literal(index, node, predicate) do
      nil -> {:ok, nil}
      value -> safe_atom(value, subject) |> wrap_error()
    end
  end

  defp wrap_error({:ok, _} = ok), do: ok
  defp wrap_error({:error, _} = error), do: error

  defp name_list(nil, _subject), do: {:ok, nil}

  defp name_list(value, subject) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reduce_while({:ok, []}, fn name, {:ok, acc} ->
      case safe_atom(name, subject) do
        {:ok, atom} -> {:cont, {:ok, [atom | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, names} -> {:ok, Enum.reverse(names)}
      other -> other
    end
  end

  defp parse_actions(index, shape, subject) do
    objects(index, shape, @r2ml <> "action")
    |> Enum.sort_by(&term_sort_key(&1, index))
    |> Enum.reduce_while({:ok, []}, fn node, {:ok, acc} ->
      case parse_action(index, node, subject) do
        {:ok, action} -> {:cont, {:ok, [action | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, actions} -> {:ok, Enum.reverse(actions)}
      other -> other
    end
  end

  defp parse_action(index, node, subject) do
    with {:ok, name} <- required_literal(index, node, @r2ml <> "actionName", subject),
         {:ok, name} <- safe_atom(name, subject),
         {:ok, kind} <- required_literal(index, node, @r2ml <> "actionKind", subject),
         {:ok, kind} <- action_kind(kind, subject),
         {:ok, accept} <- name_list(optional_literal(index, node, @r2ml <> "accept"), subject),
         {:ok, arguments} <- parse_arguments(index, node, subject) do
      {:ok,
       %{
         name: name,
         kind: kind,
         input_shape: %{
           accept: accept,
           primary?: optional_boolean(index, node, @r2ml <> "primary", false),
           arguments: arguments
         }
       }}
    end
  end

  defp action_kind(kind, _) when kind in ["create", "update", "read", "destroy"],
    do: {:ok, String.to_existing_atom(kind)}

  defp action_kind(kind, subject),
    do: incomplete(subject, "r2ml:actionKind must be create|update|read|destroy", %{got: kind})

  defp parse_arguments(index, node, subject) do
    objects(index, node, @r2ml <> "argument")
    |> Enum.sort_by(&term_sort_key(&1, index))
    |> Enum.reduce_while({:ok, []}, fn arg, {:ok, acc} ->
      with {:ok, name} <- required_literal(index, arg, @r2ml <> "argName", subject),
           {:ok, name} <- safe_atom(name, subject),
           {:ok, type} <- required_literal(index, arg, @r2ml <> "argType", subject),
           {:ok, type} <- arg_type(type, subject) do
        {:cont,
         {:ok,
          [%{name: name, type: type, allow_nil?: optional_boolean(index, arg, @r2ml <> "argAllowNil", true)} | acc]}}
      else
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, args} -> {:ok, Enum.reverse(args)}
      other -> other
    end
  end

  defp arg_type(type, subject) do
    case Enum.find(AshR2RML.Semantic.Extensions.arg_types(), &(Atom.to_string(&1) == type)) do
      nil -> incomplete(subject, "r2ml:argType is not a supported Ash type", %{got: type})
      atom -> {:ok, atom}
    end
  end

  defp parse_policies(index, shape, subject) do
    objects(index, shape, @r2ml <> "policy")
    |> Enum.sort_by(&term_sort_key(&1, index))
    |> Enum.reduce_while({:ok, []}, fn node, {:ok, acc} ->
      with {:ok, name} <- required_literal(index, node, @r2ml <> "policyName", subject),
           {:ok, name} <- safe_atom(name, subject),
           {:ok, type} <- required_literal(index, node, @r2ml <> "actionType", subject),
           {:ok, type} <- action_kind(type, subject) do
        expression = %{
          action_type: type,
          authorize_if: module_list(index, node, "authorizeIf"),
          forbid_if: module_list(index, node, "forbidIf"),
          bypass_actor: optional_literal(index, node, @r2ml <> "bypassActor")
        }

        {:cont, {:ok, [%{name: name, effect: :deny_by_default, expression: expression} | acc]}}
      else
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, policies} -> {:ok, Enum.reverse(policies)}
      other -> other
    end
  end

  # Check modules are carried as raw strings; admission validates them as module names.
  defp module_list(index, node, predicate) do
    index
    |> objects(node, @r2ml <> predicate)
    |> Enum.map(&(&1 |> literal_value() |> maybe_to_string()))
    |> Enum.flat_map(&String.split(&1 || "", ",", trim: true))
    |> Enum.map(&String.trim/1)
  end

  defp parse_state_machine(index, shape, subject) do
    with {:ok, node} <- single_node(index, shape, "stateMachine", subject) do
      if is_nil(node) do
        {:ok, nil}
      else
        with {:ok, attribute} <- required_literal(index, node, @r2ml <> "stateAttribute", subject),
             {:ok, attribute} <- safe_atom(attribute, subject),
             {:ok, initial} <- required_literal(index, node, @r2ml <> "initial", subject),
             {:ok, initial} <- safe_atom(initial, subject),
             {:ok, terminal} <- name_list(optional_literal(index, node, @r2ml <> "terminal"), subject),
             {:ok, transitions} <- parse_transitions(index, node, subject) do
          {:ok, %{attribute: attribute, initial: initial, terminal: terminal || [], transitions: transitions}}
        end
      end
    end
  end

  defp parse_transitions(index, node, subject) do
    objects(index, node, @r2ml <> "transition")
    |> Enum.sort_by(&term_sort_key(&1, index))
    |> Enum.reduce_while({:ok, []}, fn transition, {:ok, acc} ->
      with {:ok, action} <- required_literal(index, transition, @r2ml <> "action", subject),
           {:ok, action} <- safe_atom(action, subject),
           {:ok, from} <- required_literal(index, transition, @r2ml <> "from", subject),
           {:ok, from} <- name_list(from, subject),
           {:ok, to} <- required_literal(index, transition, @r2ml <> "to", subject),
           {:ok, to} <- safe_atom(to, subject) do
        {:cont, {:ok, [%{action: action, from: from, to: to} | acc]}}
      else
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, transitions} -> {:ok, Enum.reverse(transitions)}
      other -> other
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

  # Blank-node labels are parser-assigned and unstable across runs and statement orders. Every
  # label that can reach a hash, the IR, or a projection is content-derived instead: the hash of
  # the node's own outgoing subgraph (recursively), independent of the parser's label.
  defp term_sort_key(%RDF.IRI{} = iri, _index), do: RDF.IRI.to_string(iri)
  defp term_sort_key(%RDF.BlankNode{} = bnode, index), do: "_:c" <> canon_label(index, bnode, [])
  defp term_sort_key(term, _index), do: inspect(term)

  defp canon_label(index, node, seen) do
    if node in seen do
      "cycle"
    else
      index
      |> Map.get(node, %{})
      |> Enum.flat_map(fn {predicate, objects} ->
        Enum.map(objects, &{predicate, canon_term(index, &1, [node | seen])})
      end)
      |> Enum.sort()
      |> canonical_hash()
    end
  end

  defp canon_term(index, %RDF.BlankNode{} = bnode, seen), do: {:bnode, canon_label(index, bnode, seen)}
  defp canon_term(_index, %RDF.IRI{} = iri, _seen), do: {:iri, RDF.IRI.to_string(iri)}

  defp canon_term(_index, %RDF.Literal{} = literal, _seen),
    do:
      {:literal, RDF.Literal.lexical(literal), literal |> RDF.Literal.datatype_id() |> to_string(),
       RDF.Literal.language(literal)}

  defp canon_term(_index, other, _seen), do: {:other, inspect(other)}

  defp graph_hash(statements, index) do
    statements
    |> Enum.map(fn statement ->
      {subject, predicate, object} = triple(statement)
      {canon_term(index, subject, []), iri_string(predicate), canon_term(index, object, [])}
    end)
    |> Enum.uniq()
    |> Enum.sort()
    |> canonical_hash()
  end

  defp triple({s, p, o}), do: {s, p, o}
  defp triple({s, p, o, _}), do: {s, p, o}

  defp canonical_hash(term), do: sha256(:erlang.term_to_binary(term, [:deterministic]))

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
