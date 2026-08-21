# SPDX-FileCopyrightText: 2026 ash_r2ml contributors <https://github.com/seanchatmangpt/ash_r2ml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2ml.Semantic.Ecto do
  @moduledoc """
  Manufactures an Ecto migration source projection from `AshR2ml.SemanticIR`.

  The renderer is pure CONSTRUCT: it returns source text and never runs a
  migration. Unknown Ash-to-Ecto type projections fail closed.
  """

  alias AshR2ml.{Refusal, SemanticIR}
  alias SemanticIR.Relationship

  @types %{
    string: :text,
    boolean: :boolean,
    integer: :bigint,
    float: :float,
    decimal: :decimal,
    date: :date,
    utc_datetime: :utc_datetime,
    utc_datetime_usec: :utc_datetime_usec,
    uuid: :uuid
  }

  @spec render(SemanticIR.t()) :: {:ok, String.t()} | {:error, Refusal.t()}
  def render(%SemanticIR{resources: resources}) do
    resources = Enum.sort_by(resources, & &1.table)

    with :ok <- verify_types(resources) do
      tables = Enum.map_join(resources, "\n\n", &render_table(&1, resources))
      join_tables = resources |> Enum.flat_map(&render_join_tables(&1, resources)) |> Enum.join("\n\n")
      indexes = resources |> Enum.flat_map(&render_identity_indexes/1) |> Enum.join("\n")

      body =
        [tables, join_tables, indexes]
        |> Enum.reject(&(&1 == ""))
        |> Enum.join("\n\n")
        |> indent(4)

      {:ok,
       """
       defmodule AshR2ml.Generated.SemanticSchemaMigration do
         use Ecto.Migration

         def change do
       #{body}
         end
       end
       """
       |> String.trim()
       |> Kernel.<>("\n")}
    end
  end

  defp verify_types(resources) do
    case Enum.find_value(resources, fn resource ->
           Enum.find_value(resource.attributes, fn attribute ->
             if ecto_type(attribute.ash_type) do
               nil
             else
               {resource, attribute}
             end
           end)
         end) do
      nil ->
        :ok

      {resource, attribute} ->
        {:error,
         Refusal.new(
           :REFUSED_DATATYPE_CAST_NOT_LOSSLESS,
           {resource.module, attribute.name},
           "Ash type has no admitted Ecto migration projection",
           %{ash_type: inspect(attribute.ash_type), postgres_type: attribute.postgres_type}
         )}
    end
  end

  defp render_table(resource, resources) do
    fk_by_source =
      resource.relationships
      |> Enum.filter(&(&1.storage_strategy == :foreign_key))
      |> Map.new(&{&1.source_key, &1})

    fields =
      Enum.map_join(resource.attributes, "\n", fn attribute ->
        primary? = primary_key?(resource, attribute.name)
        null? = if primary?, do: false, else: attribute.nullable

        type_expression =
          case Map.get(fk_by_source, attribute.name) do
            nil ->
              inspect(ecto_type(attribute.ash_type))

            relationship ->
              destination = Enum.find(resources, &(&1.class_iri == relationship.target_class))
              destination_attribute = Enum.find(destination.attributes, &(&1.name == relationship.destination_key))

              "references(#{inspect(String.to_atom(destination.table))}, " <>
                "column: #{inspect(String.to_atom(destination_attribute.column))}, " <>
                "type: #{inspect(ecto_type(destination_attribute.ash_type))}, on_delete: :nothing)"
          end

        "add #{inspect(String.to_atom(attribute.column))}, #{type_expression}, " <>
          "null: #{inspect(null?)}, primary_key: #{inspect(primary?)}"
      end)

    """
    create table(#{inspect(String.to_atom(resource.table))}, primary_key: false) do
    #{indent(fields, 2)}
    end
    """
    |> String.trim()
  end

  defp render_join_tables(resource, resources) do
    for %Relationship{storage_strategy: :join_table} = relationship <- resource.relationships do
      destination = Enum.find(resources, &(&1.class_iri == relationship.target_class))
      source_attribute = Enum.find(resource.attributes, &(&1.name == relationship.source_key))
      destination_attribute = Enum.find(destination.attributes, &(&1.name == relationship.destination_key))

      """
      create table(#{inspect(String.to_atom(relationship.join_table))}, primary_key: false) do
        add #{inspect(String.to_atom(relationship.source_join_column))},
          references(#{inspect(String.to_atom(resource.table))}, column: #{inspect(String.to_atom(source_attribute.column))}, type: #{inspect(ecto_type(source_attribute.ash_type))}, on_delete: :nothing),
          null: false,
          primary_key: true

        add #{inspect(String.to_atom(relationship.destination_join_column))},
          references(#{inspect(String.to_atom(destination.table))}, column: #{inspect(String.to_atom(destination_attribute.column))}, type: #{inspect(ecto_type(destination_attribute.ash_type))}, on_delete: :nothing),
          null: false,
          primary_key: true
      end
      """
      |> String.trim()
    end
  end

  defp render_identity_indexes(resource) do
    resource.identities
    |> Enum.reject(& &1.primary?)
    |> Enum.map(fn identity ->
      columns =
        identity.keys
        |> Enum.map(fn key -> Enum.find(resource.attributes, &(&1.name == key)).column end)
        |> Enum.map(&String.to_atom/1)

      name = String.to_atom(resource.table <> "_" <> to_string(identity.name) <> "_index")

      "create unique_index(#{inspect(String.to_atom(resource.table))}, #{inspect(columns)}, name: #{inspect(name)})"
    end)
  end

  defp primary_key?(resource, attribute_name) do
    case Enum.find(resource.identities, & &1.primary?) do
      nil -> false
      identity -> attribute_name in identity.keys
    end
  end

  defp ecto_type(type) when is_atom(type), do: Map.get(@types, type)
  defp ecto_type(_), do: nil

  defp indent(text, spaces) do
    prefix = String.duplicate(" ", spaces)
    text |> String.split("\n") |> Enum.map_join("\n", &(prefix <> &1))
  end
end
