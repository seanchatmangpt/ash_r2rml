# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.VerifyMapping do
  @moduledoc false
  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl) do
    resource = Verifier.get_persisted(dsl, :module)
    table_name = Verifier.get_option(dsl, [:r2rml], :table_name, nil)
    sql_query = Verifier.get_option(dsl, [:r2rml], :sql_query, nil)
    class_iri = Verifier.get_option(dsl, [:r2rml], :class_iri)
    subject_template = Verifier.get_option(dsl, [:r2rml], :subject_template)
    graph_iri = Verifier.get_option(dsl, [:r2rml], :graph_iri, nil)
    attributes = Verifier.get_option(dsl, [:r2rml], :attribute_mappings, [])
    typed_attributes = Verifier.get_option(dsl, [:r2rml], :typed_attribute_mappings, [])
    relationships = Verifier.get_option(dsl, [:r2rml], :relationship_mappings, [])

    with :ok <- exactly_one_logical_table(table_name, sql_query),
         :ok <- absolute_iri(class_iri, :class_iri),
         :ok <- optional_absolute_iri(graph_iri, :graph_iri),
         :ok <- valid_predicates(attributes, typed_attributes, relationships),
         :ok <- known_attributes(resource, attributes, typed_attributes),
         :ok <- known_relationships(resource, relationships),
         :ok <- unique_attribute_mapping(attributes, typed_attributes),
         :ok <- primary_key_in_template(resource, subject_template) do
      :ok
    else
      {:error, message} ->
        {:error, DslError.exception(module: resource, path: [:r2rml], message: message)}
    end
  end

  defp exactly_one_logical_table(table, query) do
    case {present?(table), present?(query)} do
      {true, false} -> :ok
      {false, true} -> :ok
      _ -> {:error, "exactly one of table_name or sql_query must be configured"}
    end
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp absolute_iri(value, field) when is_binary(value) do
    case URI.parse(value) do
      %URI{scheme: scheme} when is_binary(scheme) and scheme != "" -> :ok
      _ -> {:error, "#{field} must be an absolute IRI, got: #{inspect(value)}"}
    end
  end

  defp absolute_iri(value, field),
    do: {:error, "#{field} must be an absolute IRI, got: #{inspect(value)}"}

  defp optional_absolute_iri(nil, _field), do: :ok
  defp optional_absolute_iri(value, field), do: absolute_iri(value, field)

  defp valid_predicates(attributes, typed_attributes, relationships) do
    predicates =
      Enum.map(attributes, &elem(&1, 1)) ++
        Enum.map(typed_attributes, &elem(&1, 1)) ++
        Enum.map(relationships, &elem(&1, 1))

    datatypes = Enum.map(typed_attributes, &elem(&1, 2))

    Enum.reduce_while(predicates ++ datatypes, :ok, fn iri, :ok ->
      case absolute_iri(iri, :predicate_or_datatype_iri) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp known_attributes(resource, attributes, typed_attributes) do
    names = Enum.map(attributes, &elem(&1, 0)) ++ Enum.map(typed_attributes, &elem(&1, 0))
    unknown = Enum.reject(names, &Ash.Resource.Info.attribute(resource, &1))

    if unknown == [],
      do: :ok,
      else: {:error, "attribute mappings reference unknown attributes: #{inspect(unknown)}"}
  end

  defp known_relationships(resource, relationships) do
    names = Enum.map(relationships, &elem(&1, 0))

    invalid =
      Enum.filter(names, fn name ->
        case Ash.Resource.Info.relationship(resource, name) do
          nil -> true
          rel -> is_nil(rel.source_attribute) or is_nil(rel.destination_attribute)
        end
      end)

    if invalid == [],
      do: :ok,
      else:
        {:error,
         "relationship mappings must reference relationships with source and destination attributes: #{inspect(invalid)}"}
  end

  defp unique_attribute_mapping(attributes, typed_attributes) do
    names = Enum.map(attributes, &elem(&1, 0)) ++ Enum.map(typed_attributes, &elem(&1, 0))
    duplicates = names -- Enum.uniq(names)

    if duplicates == [],
      do: :ok,
      else: {:error, "attributes may be mapped only once: #{inspect(Enum.uniq(duplicates))}"}
  end

  defp primary_key_in_template(resource, template) when is_binary(template) do
    missing =
      resource
      |> Ash.Resource.Info.primary_key()
      |> Enum.reject(fn key ->
        attribute = Ash.Resource.Info.attribute(resource, key)
        column = to_string(attribute.source || attribute.name)
        String.contains?(template, "{" <> column <> "}")
      end)

    if missing == [],
      do: :ok,
      else: {:error, "subject_template must contain every primary-key column placeholder; missing #{inspect(missing)}"}
  end

  defp primary_key_in_template(_resource, value),
    do: {:error, "subject_template must be a string, got: #{inspect(value)}"}
end
