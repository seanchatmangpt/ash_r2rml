# SPDX-FileCopyrightText: 2026 ash_r2ml contributors <https://github.com/seanchatmangpt/ash_r2ml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2ML.Compiler do
  @moduledoc """
  Public compiler boundary.

  Ash-first resources and ontology-first admitted profiles both converge on one
  dependency-closed `AshR2ML.Mapping.Bundle`. Serialization is a downstream
  operation over this bundle.
  """

  alias AshR2ML.Mapping.{Bundle, Resource}
  alias AshR2ML.Refusal

  @spec compile_resource(module()) :: {:ok, Resource.t()} | {:error, Refusal.t()}
  def compile_resource(resource) do
    with {:ok, mapping} <- AshR2ML.Resource.Info.mapping_result(resource),
         {:ok, enriched} <- enrich_mapping(mapping) do
      case AshR2ML.Mapping.validate(enriched) do
        :ok -> {:ok, enriched}
        {:error, [first | _]} -> {:error, first}
      end
    end
  end

  @spec compile_resources(module() | [module()]) :: {:ok, Bundle.t()} | {:error, Refusal.t()}
  def compile_resources(resources) do
    resources
    |> List.wrap()
    |> do_closure(MapSet.new(), [])
    |> case do
      {:ok, mappings} ->
        bundle = %Bundle{resources: mappings} |> AshR2ML.Mapping.normalize()

        case AshR2ML.Mapping.validate(bundle) do
          :ok -> {:ok, bundle}
          {:error, [first | _]} -> {:error, first}
        end

      error -> error
    end
  end

  @spec compile_profile(map()) :: {:ok, Bundle.t()} | {:error, term()}
  def compile_profile(profile) do
    with {:ok, semantic_ir} <- AshR2ml.Admission.admit(profile),
         {:ok, bundle} <- AshR2ML.SemanticAdapter.to_mapping(semantic_ir) do
      case AshR2ML.Mapping.validate(bundle) do
        :ok -> {:ok, AshR2ML.Mapping.normalize(bundle)}
        {:error, refusals} -> {:error, refusals}
      end
    end
  end

  defp do_closure([], _seen, acc), do: {:ok, Enum.reverse(acc)}

  defp do_closure([resource | rest], seen, acc) do
    if MapSet.member?(seen, resource) do
      do_closure(rest, seen, acc)
    else
      with {:ok, mapping} <- compile_resource(resource) do
        destinations = Enum.map(mapping.reference_object_maps, & &1.parent_resource)

        do_closure(
          rest ++ destinations,
          MapSet.put(seen, resource),
          [mapping | acc]
        )
      end
    end
  end

  defp enrich_mapping(%Resource{} = mapping) do
    references =
      Enum.reduce_while(mapping.reference_object_maps, {:ok, []}, fn reference, {:ok, acc} ->
        case enrich_reference(reference) do
          {:ok, value} -> {:cont, {:ok, [value | acc]}}
          {:error, refusal} -> {:halt, {:error, refusal}}
        end
      end)

    case references do
      {:ok, values} -> {:ok, %{mapping | reference_object_maps: Enum.reverse(values)}}
      error -> error
    end
  end

  defp enrich_reference(%{metadata: %{kind: :many_to_many, through: through}} = reference) do
    case AshR2ML.Introspection.logical_table(through) do
      {:ok, logical_table} ->
        metadata = Map.put(reference.metadata, :through_logical_table, logical_table)
        {:ok, %{reference | metadata: metadata}}

      {:error, refusal} -> {:error, refusal}
    end
  end

  defp enrich_reference(reference), do: {:ok, reference}
end

defmodule AshR2ML.SemanticAdapter do
  @moduledoc "Lowers ontology-first SemanticIR into the canonical public mapping IR."

  alias AshR2ML.Mapping.{
    Bundle,
    Datatype,
    JoinCondition,
    LogicalTable,
    ObjectMap,
    PredicateObjectMap,
    ReferenceObjectMap,
    Resource,
    SubjectMap
  }
  alias AshR2ML.Refusal
  alias AshR2ml.SemanticIR.Relationship

  @spec to_mapping(AshR2ml.SemanticIR.t()) :: {:ok, Bundle.t()} | {:error, Refusal.t()}
  def to_mapping(%AshR2ml.SemanticIR{resources: resources}) do
    by_class = Map.new(resources, &{&1.class_iri, &1})

    Enum.reduce_while(resources, {:ok, []}, fn resource, {:ok, acc} ->
      case convert_resource(resource, by_class) do
        {:ok, mapping} -> {:cont, {:ok, [mapping | acc]}}
        {:error, refusal} -> {:halt, {:error, refusal}}
      end
    end)
    |> case do
      {:ok, mappings} -> {:ok, %Bundle{resources: Enum.reverse(mappings)} |> AshR2ML.Mapping.normalize()}
      error -> error
    end
  end

  defp convert_resource(resource, by_class) do
    with {:ok, references} <- convert_references(resource, by_class) do
      properties =
        Enum.map(resource.attributes, fn attribute ->
          %PredicateObjectMap{
            attribute: attribute.name,
            predicate_iri: attribute.predicate_iri,
            object_map: %ObjectMap{
              strategy: :column,
              value: attribute.column,
              datatype: %Datatype{
                ash_type: attribute.ash_type,
                rdf_datatype: attribute.datatype_iri,
                storage_type: attribute.postgres_type
              },
              term_type: :literal
            }
          }
        end)

      attribute_columns = Map.new(resource.attributes, &{&1.name, &1.column})

      {:ok,
       %Resource{
         ash_resource: resource.module,
         class_iris: [resource.class_iri],
         logical_table: %LogicalTable{table_name: resource.table},
         subject_map: %SubjectMap{
           strategy: :template,
           value: resource.subject_template,
           term_type: :iri
         },
         predicate_object_maps: properties,
         reference_object_maps: references,
         identities: Enum.map(resource.identities, & &1.keys),
         metadata: %{
           attribute_columns: attribute_columns,
           shape_iri: resource.shape_iri,
           provenance: resource.provenance,
           source: :ontology_first
         }
       }
       |> AshR2ML.Mapping.normalize()}
    end
  end

  defp convert_references(resource, by_class) do
    Enum.reduce_while(resource.relationships, {:ok, []}, fn relationship, {:ok, acc} ->
      destination = Map.get(by_class, relationship.target_class)

      cond do
        is_nil(destination) ->
          {:halt,
           {:error,
            Refusal.new(
              :REFUSED_RELATIONSHIP_TARGET_UNMAPPED,
              {resource.module, relationship.name},
              "ontology-first relationship target is absent from admitted SemanticIR",
              %{target_class: relationship.target_class}
            )}}

        relationship.storage_strategy == :foreign_key ->
          child = attribute_column(resource, relationship.source_key)
          parent = attribute_column(destination, relationship.destination_key)

          mapping = %ReferenceObjectMap{
            relationship: relationship.name,
            predicate_iri: relationship.predicate_iri,
            inverse_predicate: relationship.inverse_predicate,
            parent_resource: destination.module,
            joins: [%JoinCondition{child: child, parent: parent}],
            metadata: %{kind: :foreign_key, cardinality: relationship.cardinality}
          }

          {:cont, {:ok, [mapping | acc]}}

        relationship.storage_strategy == :join_table ->
          source_parent = attribute_column(resource, relationship.source_key)
          destination_parent = attribute_column(destination, relationship.destination_key)

          metadata = %{
            kind: :many_to_many,
            cardinality: :many,
            through_logical_table: %LogicalTable{table_name: relationship.join_table},
            source_parent_column: source_parent,
            source_join_column: relationship.source_join_column,
            destination_join_column: relationship.destination_join_column,
            destination_parent_column: destination_parent
          }

          mapping = %ReferenceObjectMap{
            relationship: relationship.name,
            predicate_iri: relationship.predicate_iri,
            inverse_predicate: relationship.inverse_predicate,
            parent_resource: destination.module,
            joins: [],
            metadata: metadata
          }

          {:cont, {:ok, [mapping | acc]}}

        relationship.storage_strategy == :association_resource ->
          {:halt,
           {:error,
            Refusal.new(
              :REFUSED_AMBIGUOUS_RELATIONSHIP,
              {resource.module, relationship.name},
              "association-resource semantics must be represented by an admitted resource before public mapping compilation",
              %{association_resource: relationship.association_resource}
            )}}

        true ->
          {:halt,
           {:error,
            Refusal.new(
              :REFUSED_AMBIGUOUS_RELATIONSHIP,
              {resource.module, relationship.name},
              "ontology-first relationship storage remains unresolved",
              %{storage_strategy: relationship.storage_strategy, candidates: relationship.storage_candidates}
            )}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp attribute_column(resource, name) do
    case Enum.find(resource.attributes, &(&1.name == name)) do
      nil -> to_string(name)
      attribute -> attribute.column
    end
  end
end
