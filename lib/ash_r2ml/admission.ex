# SPDX-FileCopyrightText: 2026 ash_r2ml contributors <https://github.com/seanchatmangpt/ash_r2ml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2ml.Admission do
  @moduledoc """
  Admits a closed operational application profile into `AshR2ml.SemanticIR`.

  This module deliberately does not attempt arbitrary OWL-to-SQL compilation.
  Its input is the normalized result of ontology/profile/SHACL processing: the
  point where cardinality, datatype, identity, and relational-selection evidence
  is explicit enough to manufacture executable projections.
  """

  alias AshR2ml.{DfCM, Refusal, SemanticIR}
  alias AshR2ml.SemanticIR.{Action, Attribute, Identity, Policy, Relationship, Resource}

  @xsd %{
    "http://www.w3.org/2001/XMLSchema#string" => {:string, "TEXT"},
    "http://www.w3.org/2001/XMLSchema#boolean" => {:boolean, "BOOLEAN"},
    "http://www.w3.org/2001/XMLSchema#integer" => {:integer, "BIGINT"},
    "http://www.w3.org/2001/XMLSchema#int" => {:integer, "INTEGER"},
    "http://www.w3.org/2001/XMLSchema#decimal" => {:decimal, "NUMERIC"},
    "http://www.w3.org/2001/XMLSchema#double" => {:float, "DOUBLE PRECISION"},
    "http://www.w3.org/2001/XMLSchema#date" => {:date, "DATE"},
    "http://www.w3.org/2001/XMLSchema#dateTime" => {:utc_datetime_usec, "TIMESTAMPTZ"},
    "http://www.w3.org/2001/XMLSchema#anyURI" => {:string, "TEXT"}
  }

  @spec admit(map()) :: {:ok, SemanticIR.t()} | {:error, [Refusal.t()]}
  def admit(profile) when is_map(profile) do
    with {:ok, resources} <- normalize_resources(get(profile, :resources, [])),
         [] <- verify_resources(resources) do
      {:ok,
       %SemanticIR{
         ontology_hash: get(profile, :ontology_hash),
         profile_hash: get(profile, :profile_hash),
         shacl_hash: get(profile, :shacl_hash),
         resources: Enum.sort_by(resources, & &1.class_iri)
       }}
    else
      {:error, refusals} -> {:error, List.wrap(refusals)}
      refusals when is_list(refusals) -> {:error, refusals}
    end
  end

  def admit(other) do
    {:error,
     [
       Refusal.new(
         :REFUSED_UNPROVEN_EQUIVALENCE,
         :profile,
         "expected normalized application profile map",
         %{got: inspect(other)}
       )
     ]}
  end

  @doc "Returns the datatype correspondence used when SHACL closes the representation choice."
  def datatype_projection(datatype_iri), do: Map.get(@xsd, datatype_iri)

  defp normalize_resources(resources) when is_list(resources) do
    Enum.reduce_while(resources, {:ok, []}, fn raw, {:ok, acc} ->
      case normalize_resource(raw) do
        {:ok, resource} -> {:cont, {:ok, [resource | acc]}}
        {:error, refusal} -> {:halt, {:error, [refusal]}}
      end
    end)
    |> reverse_ok()
  end

  defp normalize_resources(_) do
    {:error,
     [Refusal.new(:REFUSED_UNPROVEN_EQUIVALENCE, :resources, "profile resources must be a list")]}
  end

  defp normalize_resource(raw) when is_map(raw) do
    with {:ok, attributes} <- normalize_attributes(get(raw, :attributes, [])),
         {:ok, identities} <- normalize_identities(get(raw, :identities, [])),
         {:ok, relationships} <- normalize_relationships(get(raw, :relationships, [])) do
      {:ok,
       %Resource{
         iri: get(raw, :iri) || get(raw, :class_iri),
         class_iri: get(raw, :class_iri),
         shape_iri: get(raw, :shape_iri),
         module: get(raw, :module),
         repo_module: get(raw, :repo_module),
         table: get(raw, :table),
         subject_template: get(raw, :subject_template),
         identities: sort_identities(identities),
         attributes: Enum.sort_by(attributes, &to_string(&1.name)),
         relationships: Enum.sort_by(relationships, &to_string(&1.name)),
         actions: raw |> get(:actions, []) |> normalize_actions() |> Enum.sort_by(&to_string(&1.name)),
         policies: raw |> get(:policies, []) |> normalize_policies() |> Enum.sort_by(&to_string(&1.name)),
         provenance: get(raw, :provenance, %{})
       }}
    end
  end

  defp normalize_resource(other) do
    {:error,
     Refusal.new(:REFUSED_UNMAPPED_RESOURCE_CLASS, other, "resource profile entry must be a map")}
  end

  defp normalize_attributes(values) when is_list(values) do
    Enum.reduce_while(values, {:ok, []}, fn raw, {:ok, acc} ->
      datatype = get(raw, :datatype_iri)
      projection = datatype_projection(datatype)
      ash_type = get(raw, :ash_type) || (projection && elem(projection, 0))
      postgres_type = get(raw, :postgres_type) || (projection && elem(projection, 1))
      name = get(raw, :name)
      min_count = get(raw, :min_count, 0)
      max_count = get(raw, :max_count, 1)

      cond do
        is_nil(get(raw, :predicate_iri)) ->
          {:halt,
           {:error,
            Refusal.new(
              :REFUSED_ATTRIBUTE_WITHOUT_PREDICATE,
              name,
              "admitted datatype property has no predicate IRI"
            )}}

        is_nil(ash_type) or is_nil(postgres_type) ->
          {:halt,
           {:error,
            Refusal.new(
              :REFUSED_DATATYPE_CAST_NOT_LOSSLESS,
              name,
              "datatype has no admitted Ash/PostgreSQL projection; provide both explicitly",
              %{datatype_iri: datatype}
            )}}

        true ->
          attribute = %Attribute{
            name: name,
            column: get(raw, :column) || default_column(name),
            predicate_iri: get(raw, :predicate_iri),
            datatype_iri: datatype,
            ash_type: ash_type,
            postgres_type: postgres_type,
            min_count: min_count,
            max_count: max_count,
            nullable: get(raw, :nullable, min_count == 0),
            identity?: get(raw, :identity?, false),
            provenance: get(raw, :provenance, %{})
          }

          {:cont, {:ok, [attribute | acc]}}
      end
    end)
    |> reverse_ok()
  end

  defp normalize_attributes(_) do
    {:error, Refusal.new(:REFUSED_UNPROVEN_EQUIVALENCE, :attributes, "attributes must be a list")}
  end

  defp normalize_identities(values) when is_list(values) do
    values
    |> Enum.with_index()
    |> Enum.map(fn {raw, index} ->
      %Identity{
        name: get(raw, :name, String.to_atom("semantic_identity_#{index + 1}")),
        keys: get(raw, :keys, []),
        template: get(raw, :template),
        primary?: get(raw, :primary?, index == 0)
      }
    end)
    |> then(&{:ok, &1})
  end

  defp normalize_identities(_) do
    {:error,
     Refusal.new(:REFUSED_NON_UNIQUE_SEMANTIC_IDENTITY, :identities, "identities must be a list")}
  end

  defp normalize_relationships(values) when is_list(values) do
    Enum.reduce_while(values, {:ok, []}, fn raw, {:ok, acc} ->
      relationship = %Relationship{
        name: get(raw, :name),
        predicate_iri: get(raw, :predicate_iri),
        inverse_predicate: get(raw, :inverse_predicate),
        source_class: get(raw, :source_class),
        target_class: get(raw, :target_class),
        source_key: get(raw, :source_key),
        destination_key: get(raw, :destination_key),
        join_table: get(raw, :join_table),
        source_join_column: get(raw, :source_join_column),
        destination_join_column: get(raw, :destination_join_column),
        association_resource: get(raw, :association_resource),
        storage_strategy: normalize_strategy(get(raw, :storage_strategy)),
        min_count: get(raw, :min_count, 0),
        max_count: get(raw, :max_count),
        cardinality: if(get(raw, :max_count) == 1, do: :one, else: :many),
        properties: get(raw, :properties, []),
        provenance: get(raw, :provenance, %{})
      }

      case DfCM.select(relationship) do
        {:ok, selected} -> {:cont, {:ok, [selected | acc]}}
        {:error, refusal} -> {:halt, {:error, refusal}}
      end
    end)
    |> reverse_ok()
  end

  defp normalize_relationships(_) do
    {:error,
     Refusal.new(:REFUSED_UNPROVEN_EQUIVALENCE, :relationships, "relationships must be a list")}
  end

  defp normalize_actions(values) when is_list(values) do
    Enum.map(values, fn raw ->
      %Action{
        name: get(raw, :name),
        kind: get(raw, :kind),
        input_shape: get(raw, :input_shape),
        output_shape: get(raw, :output_shape),
        provenance: get(raw, :provenance, %{})
      }
    end)
  end

  defp normalize_actions(_), do: []

  defp normalize_policies(values) when is_list(values) do
    Enum.map(values, fn raw ->
      %Policy{
        name: get(raw, :name),
        effect: get(raw, :effect),
        expression: get(raw, :expression),
        odrl_iri: get(raw, :odrl_iri),
        provenance: get(raw, :provenance, %{})
      }
    end)
  end

  defp normalize_policies(_), do: []

  defp verify_resources(resources) do
    by_class = Map.new(resources, &{&1.class_iri, &1})

    duplicate_classes = duplicated(Enum.map(resources, & &1.class_iri))
    duplicate_tables = duplicated(Enum.map(resources, & &1.table))
    duplicate_modules = duplicated(Enum.map(resources, & &1.module))

    global =
      []
      |> maybe_add(duplicate_classes != [], fn ->
        Refusal.new(
          :REFUSED_UNMAPPED_RESOURCE_CLASS,
          :profile,
          "each admitted class must map to exactly one resource",
          %{classes: duplicate_classes}
        )
      end)
      |> maybe_add(duplicate_tables != [], fn ->
        Refusal.new(
          :REFUSED_UNPROVEN_EQUIVALENCE,
          :profile,
          "table ownership is ambiguous across admitted resources",
          %{tables: duplicate_tables}
        )
      end)
      |> maybe_add(duplicate_modules != [], fn ->
        Refusal.new(
          :REFUSED_UNPROVEN_EQUIVALENCE,
          :profile,
          "Ash module ownership is ambiguous across admitted resources",
          %{modules: duplicate_modules}
        )
      end)

    global ++ Enum.flat_map(resources, &verify_resource(&1, by_class))
  end

  defp verify_resource(resource, by_class) do
    []
    |> require_iri(resource.class_iri, resource.module, :REFUSED_UNMAPPED_RESOURCE_CLASS)
    |> require_iri(resource.shape_iri, resource.module, :REFUSED_INVALID_IRI)
    |> require_iri(resource.iri, resource.module, :REFUSED_INVALID_IRI)
    |> require_nonempty(resource.module, resource.module, "resource module is required")
    |> require_nonempty(resource.table, resource.module, "relational table name is required")
    |> require_nonempty(resource.subject_template, resource.module, "subject template is required")
    |> Kernel.++(verify_identity(resource))
    |> Kernel.++(verify_attributes(resource))
    |> Kernel.++(verify_relationships(resource, by_class))
  end

  defp verify_identity(%Resource{identities: []} = resource) do
    [
      Refusal.new(
        :REFUSED_NON_UNIQUE_SEMANTIC_IDENTITY,
        resource.module,
        "closed relational projection requires at least one semantic identity"
      )
    ]
  end

  defp verify_identity(resource) do
    names = MapSet.new(resource.attributes, & &1.name)
    primaries = Enum.filter(resource.identities, & &1.primary?)
    primary = List.first(primaries)
    duplicate_keysets = resource.identities |> Enum.map(&Enum.sort(&1.keys)) |> duplicated()

    missing_keys =
      resource.identities
      |> Enum.flat_map(& &1.keys)
      |> Enum.uniq()
      |> Enum.reject(&MapSet.member?(names, &1))

    nullable_identity_keys =
      resource.identities
      |> Enum.flat_map(& &1.keys)
      |> Enum.uniq()
      |> Enum.filter(fn key ->
        case find_attribute(resource, key) do
          nil -> false
          attribute -> attribute.nullable or attribute.min_count < 1
        end
      end)

    template_missing =
      if primary do
        Enum.reject(primary.keys, fn key ->
          case find_attribute(resource, key) do
            nil -> false
            attribute -> String.contains?(resource.subject_template || "", "{#{attribute.column}}")
          end
        end)
      else
        []
      end

    []
    |> maybe_add(length(primaries) != 1, fn ->
      Refusal.new(
        :REFUSED_NON_UNIQUE_SEMANTIC_IDENTITY,
        resource.module,
        "exactly one primary semantic identity is required",
        %{primary_count: length(primaries)}
      )
    end)
    |> maybe_add(missing_keys != [], fn ->
      Refusal.new(
        :REFUSED_UNKNOWN_ATTRIBUTE,
        resource.module,
        "semantic identity references unknown attributes",
        %{keys: missing_keys}
      )
    end)
    |> maybe_add(nullable_identity_keys != [], fn ->
      Refusal.new(
        :REFUSED_NON_UNIQUE_SEMANTIC_IDENTITY,
        resource.module,
        "semantic identity keys must be required/non-null",
        %{keys: nullable_identity_keys}
      )
    end)
    |> maybe_add(duplicate_keysets != [], fn ->
      Refusal.new(
        :REFUSED_NON_UNIQUE_SEMANTIC_IDENTITY,
        resource.module,
        "duplicate semantic identity key sets",
        %{keysets: duplicate_keysets}
      )
    end)
    |> maybe_add(template_missing != [], fn ->
      Refusal.new(
        :REFUSED_INVALID_SUBJECT_TEMPLATE,
        resource.module,
        "subject template must contain every primary semantic identity column",
        %{missing_keys: template_missing, template: resource.subject_template}
      )
    end)
  end

  defp verify_attributes(resource) do
    names = Enum.map(resource.attributes, & &1.name)
    columns = Enum.map(resource.attributes, & &1.column)

    base =
      []
      |> maybe_add(Enum.any?(names, &(not is_atom(&1))), fn ->
        Refusal.new(:REFUSED_UNKNOWN_ATTRIBUTE, resource.module, "attribute names must be atoms")
      end)
      |> maybe_add(Enum.any?(columns, &(not nonempty_string?(&1))), fn ->
        Refusal.new(:REFUSED_UNKNOWN_ATTRIBUTE, resource.module, "attribute columns must be non-empty strings")
      end)
      |> maybe_add(duplicated(names) != [], fn ->
        Refusal.new(
          :REFUSED_UNKNOWN_ATTRIBUTE,
          resource.module,
          "duplicate attribute names",
          %{names: duplicated(names)}
        )
      end)
      |> maybe_add(duplicated(columns) != [], fn ->
        Refusal.new(
          :REFUSED_UNKNOWN_ATTRIBUTE,
          resource.module,
          "duplicate relational columns",
          %{columns: duplicated(columns)}
        )
      end)

    base ++
      Enum.flat_map(resource.attributes, fn attribute ->
        expected_nullable = attribute.min_count == 0

        []
        |> require_iri(
          attribute.predicate_iri,
          {resource.module, attribute.name},
          :REFUSED_ATTRIBUTE_WITHOUT_PREDICATE
        )
        |> require_iri(
          attribute.datatype_iri,
          {resource.module, attribute.name},
          :REFUSED_DATATYPE_CAST_NOT_LOSSLESS
        )
        |> maybe_add(not valid_cardinality?(attribute.min_count, attribute.max_count), fn ->
          Refusal.new(
            :REFUSED_CARDINALITY_STORAGE_MISMATCH,
            {resource.module, attribute.name},
            "invalid SHACL cardinality",
            %{min_count: attribute.min_count, max_count: attribute.max_count}
          )
        end)
        |> maybe_add(attribute.max_count not in [nil, 1], fn ->
          Refusal.new(
            :REFUSED_CARDINALITY_STORAGE_MISMATCH,
            {resource.module, attribute.name},
            "multi-valued datatype properties require an explicit normalized storage projection",
            %{max_count: attribute.max_count}
          )
        end)
        |> maybe_add(attribute.nullable != expected_nullable, fn ->
          Refusal.new(
            :REFUSED_CARDINALITY_STORAGE_MISMATCH,
            {resource.module, attribute.name},
            "Ash/PostgreSQL nullability must equal admitted SHACL minCount semantics",
            %{nullable: attribute.nullable, min_count: attribute.min_count}
          )
        end)
      end)
  end

  defp verify_relationships(resource, by_class) do
    Enum.flat_map(resource.relationships, fn relationship ->
      destination = Map.get(by_class, relationship.target_class)

      []
      |> require_iri(
        relationship.predicate_iri,
        {resource.module, relationship.name},
        :REFUSED_RELATIONSHIP_WITHOUT_TARGET_MAP
      )
      |> maybe_add(not valid_cardinality?(relationship.min_count, relationship.max_count), fn ->
        Refusal.new(
          :REFUSED_CARDINALITY_STORAGE_MISMATCH,
          {resource.module, relationship.name},
          "invalid relationship cardinality",
          %{min_count: relationship.min_count, max_count: relationship.max_count}
        )
      end)
      |> maybe_add(relationship.source_class != resource.class_iri, fn ->
        Refusal.new(
          :REFUSED_UNPROVEN_EQUIVALENCE,
          {resource.module, relationship.name},
          "relationship source class must equal the enclosing admitted resource class",
          %{expected: resource.class_iri, actual: relationship.source_class}
        )
      end)
      |> maybe_add(is_nil(destination), fn ->
        Refusal.new(
          :REFUSED_RELATIONSHIP_WITHOUT_TARGET_MAP,
          {resource.module, relationship.name},
          "relationship target class is not in the admitted profile",
          %{target_class: relationship.target_class}
        )
      end)
      |> Kernel.++(verify_strategy(resource, relationship, destination))
    end)
  end

  defp verify_strategy(_resource, _relationship, nil), do: []

  defp verify_strategy(resource, relationship, destination) do
    case relationship.storage_strategy do
      :foreign_key -> verify_foreign_key(resource, relationship, destination)
      :join_table -> verify_join_table(resource, relationship, destination)
      :association_resource -> verify_association_resource(relationship)
      nil -> []
      _ ->
        [
          Refusal.new(
            :REFUSED_CARDINALITY_STORAGE_MISMATCH,
            {resource.module, relationship.name},
            "unsupported relational storage strategy",
            %{strategy: relationship.storage_strategy}
          )
        ]
    end
  end

  defp verify_foreign_key(resource, relationship, destination) do
    source_attr = find_attribute(resource, relationship.source_key)
    destination_attr = find_attribute(destination, relationship.destination_key)
    expected_nullable = relationship.min_count == 0

    []
    |> maybe_add(is_nil(source_attr), fn ->
      Refusal.new(
        :REFUSED_UNKNOWN_ATTRIBUTE,
        {resource.module, relationship.name},
        "foreign-key source_key is not an admitted source attribute"
      )
    end)
    |> maybe_add(is_nil(destination_attr), fn ->
      Refusal.new(
        :REFUSED_UNKNOWN_ATTRIBUTE,
        {resource.module, relationship.name},
        "foreign-key destination_key is not an admitted target attribute"
      )
    end)
    |> maybe_add(source_attr && source_attr.nullable != expected_nullable, fn ->
      Refusal.new(
        :REFUSED_CARDINALITY_STORAGE_MISMATCH,
        {resource.module, relationship.name},
        "foreign-key source nullability must equal object-property minCount semantics",
        %{source_key: relationship.source_key, nullable: source_attr.nullable, min_count: relationship.min_count}
      )
    end)
    |> maybe_add(destination_attr && not single_column_identity_key?(destination, relationship.destination_key), fn ->
      Refusal.new(
        :REFUSED_R2RML_JOIN_KEY_NOT_UNIQUE,
        {resource.module, relationship.name},
        "R2RML parent join key must itself be an admitted single-column unique identity",
        %{destination_key: relationship.destination_key}
      )
    end)
  end

  defp verify_join_table(resource, relationship, destination) do
    required = [
      join_table: relationship.join_table,
      source_key: relationship.source_key,
      destination_key: relationship.destination_key,
      source_join_column: relationship.source_join_column,
      destination_join_column: relationship.destination_join_column
    ]

    missing = for {key, value} <- required, is_nil(value), do: key
    primary_key = single_primary_key(resource)

    []
    |> maybe_add(missing != [], fn ->
      Refusal.new(
        :REFUSED_CARDINALITY_STORAGE_MISMATCH,
        {resource.module, relationship.name},
        "join-table projection requires explicit join identity/column metadata",
        %{missing: missing}
      )
    end)
    |> maybe_add(primary_key != relationship.source_key, fn ->
      Refusal.new(
        :REFUSED_INVALID_SUBJECT_TEMPLATE,
        {resource.module, relationship.name},
        "join-table source key must be the resource's single-column primary semantic identity so its subject template can be projected losslessly",
        %{primary_key: primary_key, source_key: relationship.source_key}
      )
    end)
    |> maybe_add(not single_column_identity_key?(destination, relationship.destination_key), fn ->
      Refusal.new(
        :REFUSED_R2RML_JOIN_KEY_NOT_UNIQUE,
        {resource.module, relationship.name},
        "join-table destination key must itself be an admitted single-column unique identity",
        %{destination_key: relationship.destination_key}
      )
    end)
  end

  defp verify_association_resource(relationship) do
    if relationship.association_resource do
      []
    else
      [
        Refusal.new(
          :REFUSED_UNPROVEN_EQUIVALENCE,
          relationship.name,
          "association-resource selection must name the reified admitted resource"
        )
      ]
    end
  end

  defp find_attribute(nil, _), do: nil
  defp find_attribute(resource, name), do: Enum.find(resource.attributes, &(&1.name == name))

  defp single_column_identity_key?(nil, _), do: false

  defp single_column_identity_key?(resource, key) do
    Enum.any?(resource.identities, &(&1.keys == [key]))
  end

  defp single_primary_key(resource) do
    case Enum.find(resource.identities, & &1.primary?) do
      %Identity{keys: [key]} -> key
      _ -> nil
    end
  end

  defp require_iri(acc, value, subject, code) do
    if absolute_iri?(value) do
      acc
    else
      acc ++ [Refusal.new(code, subject, "expected absolute IRI", %{value: value})]
    end
  end

  defp require_nonempty(acc, value, subject, detail) do
    if nonempty_string?(value) or (is_atom(value) and not is_nil(value)) do
      acc
    else
      acc ++ [Refusal.new(:REFUSED_UNPROVEN_EQUIVALENCE, subject, detail, %{value: value})]
    end
  end

  defp absolute_iri?(value) when is_binary(value) do
    case URI.parse(value) do
      %URI{scheme: scheme} when is_binary(scheme) and scheme != "" -> true
      _ -> false
    end
  end

  defp absolute_iri?(_), do: false

  defp valid_cardinality?(min_count, max_count)
       when is_integer(min_count) and min_count >= 0 and
              (is_nil(max_count) or (is_integer(max_count) and max_count >= min_count)),
       do: true

  defp valid_cardinality?(_, _), do: false

  defp duplicated(values) do
    values
    |> Enum.frequencies()
    |> Enum.filter(fn {_value, count} -> count > 1 end)
    |> Enum.map(&elem(&1, 0))
  end

  defp maybe_add(acc, true, fun), do: acc ++ [fun.()]
  defp maybe_add(acc, false, _fun), do: acc

  defp reverse_ok({:ok, values}), do: {:ok, Enum.reverse(values)}
  defp reverse_ok(other), do: other

  defp sort_identities(identities) do
    Enum.sort_by(identities, fn identity -> {not identity.primary?, to_string(identity.name)} end)
  end

  defp default_column(name) when is_atom(name), do: Atom.to_string(name)
  defp default_column(name) when is_binary(name), do: name
  defp default_column(_), do: nil

  defp nonempty_string?(value), do: is_binary(value) and value != ""

  defp normalize_strategy(nil), do: nil
  defp normalize_strategy(:foreign_key), do: :foreign_key
  defp normalize_strategy(:join_table), do: :join_table
  defp normalize_strategy(:association_resource), do: :association_resource
  defp normalize_strategy("foreign_key"), do: :foreign_key
  defp normalize_strategy("join_table"), do: :join_table
  defp normalize_strategy("association_resource"), do: :association_resource
  defp normalize_strategy(value), do: {:unsupported, value}

  defp get(map, key, default \\ nil) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end
end
