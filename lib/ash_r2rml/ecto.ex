# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Semantic.Ecto do
  @moduledoc """
  Manufactures an Ecto migration source projection from `AshR2RML.SemanticIR`.

  The renderer is pure CONSTRUCT: it returns source text and never runs a
  migration. Unknown Ash-to-Ecto type projections fail closed. Base tables are
  created before foreign-key constraints so dependency cycles do not depend on
  accidental resource ordering.
  """

  alias AshR2RML.{Refusal, SemanticIR}
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
      tables = Enum.map_join(resources, "\n\n", &render_table/1)
      foreign_keys = resources |> Enum.flat_map(&render_foreign_keys(&1, resources)) |> Enum.join("\n\n")
      join_tables = resources |> Enum.flat_map(&render_join_tables(&1, resources)) |> Enum.join("\n\n")
      indexes = resources |> Enum.flat_map(&render_identity_indexes/1) |> Enum.join("\n")

      body =
        [tables, foreign_keys, join_tables, indexes]
        |> Enum.reject(&(&1 == ""))
        |> Enum.join("\n\n")
        |> indent(4)

      {:ok,
       """
       defmodule AshR2RML.Generated.SemanticSchemaMigration do
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
             if ecto_type(attribute.ash_type), do: nil, else: {resource, attribute}
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

  defp render_table(resource) do
    fields =
      Enum.map_join(resource.attributes, "\n", fn attribute ->
        primary? = primary_key?(resource, attribute.name)
        null? = if primary?, do: false, else: attribute.nullable

        "add #{atom_literal(attribute.column)}, #{inspect(ecto_type(attribute.ash_type))}, " <>
          "null: #{inspect(null?)}, primary_key: #{inspect(primary?)}"
      end)

    """
    create table(#{atom_literal(resource.table)}, primary_key: false) do
    #{indent(fields, 2)}
    end
    """
    |> String.trim()
  end

  defp render_foreign_keys(resource, resources) do
    for %Relationship{storage_strategy: :foreign_key} = relationship <- resource.relationships do
      source_attribute = Enum.find(resource.attributes, &(&1.name == relationship.source_key))
      destination = Enum.find(resources, &(&1.class_iri == relationship.target_class))
      destination_attribute = Enum.find(destination.attributes, &(&1.name == relationship.destination_key))

      """
      alter table(#{atom_literal(resource.table)}) do
        modify #{atom_literal(source_attribute.column)},
          references(#{atom_literal(destination.table)}, column: #{atom_literal(destination_attribute.column)}, type: #{inspect(ecto_type(destination_attribute.ash_type))}, on_delete: :nothing),
          from: #{inspect(ecto_type(source_attribute.ash_type))},
          null: #{inspect(source_attribute.nullable)}
      end
      """
      |> String.trim()
    end
  end

  defp render_join_tables(resource, resources) do
    for %Relationship{storage_strategy: :join_table} = relationship <- resource.relationships do
      destination = Enum.find(resources, &(&1.class_iri == relationship.target_class))
      source_attribute = Enum.find(resource.attributes, &(&1.name == relationship.source_key))
      destination_attribute = Enum.find(destination.attributes, &(&1.name == relationship.destination_key))

      """
      create table(#{atom_literal(relationship.join_table)}, primary_key: false) do
        add #{atom_literal(relationship.source_join_column)},
          references(#{atom_literal(resource.table)}, column: #{atom_literal(source_attribute.column)}, type: #{inspect(ecto_type(source_attribute.ash_type))}, on_delete: :nothing),
          null: false,
          primary_key: true

        add #{atom_literal(relationship.destination_join_column)},
          references(#{atom_literal(destination.table)}, column: #{atom_literal(destination_attribute.column)}, type: #{inspect(ecto_type(destination_attribute.ash_type))}, on_delete: :nothing),
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
        |> Enum.map_join(", ", &atom_literal/1)

      name = resource.table <> "_" <> to_string(identity.name) <> "_index"

      "create unique_index(#{atom_literal(resource.table)}, [#{columns}], name: #{atom_literal(name)})"
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

  defp atom_literal(value), do: ":" <> inspect(to_string(value))

  defp indent(text, spaces) do
    prefix = String.duplicate(" ", spaces)
    text |> String.split("\n") |> Enum.map_join("\n", &(prefix <> &1))
  end
end
