# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Temporal do
  @moduledoc """
  Declarative start/end attribute projection into OWL-Time begin/end predicates.

  A `temporal` DSL entry names a start attribute and/or an end attribute. Each
  becomes an `xsd:dateTime` literal predicate-object map:

    * start attribute -> `time:hasBeginning`
    * end attribute   -> `time:hasEnd`

  Only attributes whose Ash type is a date-time type are admitted. Date-only,
  integer and other types are refused with `REFUSED_INVALID_TERM_MAP`.

  `Ash.Type.Range` columns hold both bounds in one native range value
  (`tstzrange` etc). R2RML term maps address plain columns, so the bounds cannot
  be addressed without a `lower()`/`upper()` SQL expression. Range attributes are
  refused with a precise `UNSUPPORTED_ASH_TYPE`; declare separate start/end
  attributes and use `temporal` instead.
  """

  alias AshR2RML.Mapping.{Datatype, ObjectMap, PredicateObjectMap}
  alias AshR2RML.Refusal

  @time "http://www.w3.org/2006/time#"
  @xsd_datetime "http://www.w3.org/2001/XMLSchema#dateTime"

  @has_beginning @time <> "hasBeginning"
  @has_end @time <> "hasEnd"

  @datetime_types [
    Ash.Type.UtcDatetime,
    Ash.Type.UtcDatetimeUsec,
    Ash.Type.NaiveDatetime,
    Ash.Type.NaiveDatetimeUsec,
    Ash.Type.DateTime
  ]

  @doc "IRI of `time:hasBeginning`."
  @spec has_beginning() :: String.t()
  def has_beginning, do: @has_beginning

  @doc "IRI of `time:hasEnd`."
  @spec has_end() :: String.t()
  def has_end, do: @has_end

  @doc """
  True when the Ash type is a range type.

      iex> AshR2RML.Temporal.range_type?(Ash.Type.Range)
      true
      iex> AshR2RML.Temporal.range_type?(Ash.Type.String)
      false
  """
  @spec range_type?(term()) :: boolean()
  def range_type?(type) when is_atom(type) and not is_nil(type) do
    case AshR2RML.Datatype.Registry.unwrap_checked(type) do
      {:ok, base, _constraints} -> base == Ash.Type.Range
      {:error, _refusal} -> false
    end
  end

  def range_type?(_), do: false

  @doc """
  True when the Ash type is a date-time type admissible as a temporal bound.

      iex> AshR2RML.Temporal.datetime_type?(Ash.Type.UtcDatetime)
      true
      iex> AshR2RML.Temporal.datetime_type?(Ash.Type.Date)
      false
  """
  @spec datetime_type?(term()) :: boolean()
  def datetime_type?(type) when is_atom(type) and not is_nil(type) do
    case AshR2RML.Datatype.Registry.unwrap_checked(type) do
      {:ok, base, _constraints} -> base in @datetime_types
      {:error, _refusal} -> false
    end
  end

  def datetime_type?(_), do: false

  @doc "Typed refusal for a range-typed attribute mapped as a plain property."
  @spec range_refusal(term(), atom()) :: Refusal.t()
  def range_refusal(type, attribute) do
    Refusal.new(
      :UNSUPPORTED_ASH_TYPE,
      {type, attribute},
      "Ash.Type.Range packs both bounds into one native range value that an R2RML column " <>
        "cannot address; declare separate start/end attributes and map them with `temporal`",
      %{normalized_type: :range, attribute: attribute}
    )
  end

  @doc """
  Compiles one `temporal` entry into predicate-object maps.

  `lookup` resolves an attribute name to `{:ok, ash_type, column}` or `:error`.
  """
  @spec compile(map(), (atom() -> {:ok, term(), String.t()} | :error)) ::
          {:ok, [PredicateObjectMap.t()]} | {:error, Refusal.t()}
  def compile(%{start_attribute: nil, end_attribute: nil} = entry, _lookup) do
    {:error,
     Refusal.new(
       :REFUSED_INVALID_TERM_MAP,
       entry,
       "temporal requires at least one of start_attribute or end_attribute"
     )}
  end

  def compile(entry, lookup) do
    [{entry.start_attribute, @has_beginning}, {entry.end_attribute, @has_end}]
    |> Enum.reject(fn {attribute, _predicate} -> is_nil(attribute) end)
    |> Enum.reduce_while({:ok, []}, fn {attribute, predicate}, {:ok, acc} ->
      case one(attribute, predicate, lookup) do
        {:ok, pom} -> {:cont, {:ok, [pom | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, poms} -> {:ok, Enum.reverse(poms)}
      error -> error
    end
  end

  defp one(attribute, predicate, lookup) do
    case lookup.(attribute) do
      :error ->
        {:error,
         Refusal.new(
           :REFUSED_UNKNOWN_ATTRIBUTE,
           attribute,
           "temporal mapping references an unknown Ash attribute"
         )}

      {:ok, type, column} ->
        cond do
          range_type?(type) -> {:error, range_refusal(type, attribute)}
          datetime_type?(type) -> build(attribute, predicate, type, column)
          true -> {:error, not_datetime(attribute, type)}
        end
    end
  end

  defp build(attribute, predicate, type, column) do
    with {:ok, %Datatype{storage_type: storage}} <- AshR2RML.Datatype.Registry.resolve(type) do
      {:ok,
       %PredicateObjectMap{
         attribute: attribute,
         predicate_iri: predicate,
         object_map: %ObjectMap{
           strategy: :column,
           value: column,
           term_type: :literal,
           datatype: %Datatype{ash_type: type, rdf_datatype: @xsd_datetime, storage_type: storage}
         }
       }}
    end
  end

  defp not_datetime(attribute, type) do
    Refusal.new(
      :REFUSED_INVALID_TERM_MAP,
      attribute,
      "temporal bounds must be date-time attributes (xsd:dateTime)",
      %{attribute: attribute, ash_type: type}
    )
  end
end
