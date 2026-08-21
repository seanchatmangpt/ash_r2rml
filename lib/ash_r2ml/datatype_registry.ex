# SPDX-FileCopyrightText: 2026 ash_r2ml contributors <https://github.com/seanchatmangpt/ash_r2ml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2ML.Datatype.Registry do
  @moduledoc """
  Loss-aware built-in datatype correspondence.

  Unknown Ash types are never stringified implicitly. A caller may supply an
  explicit RDF datatype override for a custom type; otherwise resolution returns
  `UNSUPPORTED_ASH_TYPE`.
  """

  alias AshR2ML.Mapping.Datatype
  alias AshR2ML.Refusal

  @xsd "http://www.w3.org/2001/XMLSchema#"

  @builtins %{
    string: {@xsd <> "string", :text},
    boolean: {@xsd <> "boolean", :boolean},
    integer: {@xsd <> "integer", :bigint},
    float: {@xsd <> "double", :float},
    decimal: {@xsd <> "decimal", :decimal},
    date: {@xsd <> "date", :date},
    time: {@xsd <> "time", :time},
    utc_datetime: {@xsd <> "dateTime", :utc_datetime},
    utc_datetime_usec: {@xsd <> "dateTime", :utc_datetime_usec},
    naive_datetime: {@xsd <> "dateTime", :naive_datetime},
    naive_datetime_usec: {@xsd <> "dateTime", :naive_datetime_usec},
    uuid: {@xsd <> "string", :uuid},
    ci_string: {@xsd <> "string", :citext},
    atom: {@xsd <> "string", :text}
  }

  @ash_type_modules %{
    "Elixir.Ash.Type.String" => :string,
    "Elixir.Ash.Type.Boolean" => :boolean,
    "Elixir.Ash.Type.Integer" => :integer,
    "Elixir.Ash.Type.Float" => :float,
    "Elixir.Ash.Type.Decimal" => :decimal,
    "Elixir.Ash.Type.Date" => :date,
    "Elixir.Ash.Type.Time" => :time,
    "Elixir.Ash.Type.UtcDatetime" => :utc_datetime,
    "Elixir.Ash.Type.UtcDatetimeUsec" => :utc_datetime_usec,
    "Elixir.Ash.Type.NaiveDatetime" => :naive_datetime,
    "Elixir.Ash.Type.NaiveDatetimeUsec" => :naive_datetime_usec,
    "Elixir.Ash.Type.UUID" => :uuid,
    "Elixir.Ash.Type.CiString" => :ci_string,
    "Elixir.Ash.Type.Atom" => :atom
  }

  @spec resolve(term(), String.t() | nil, term() | nil) ::
          {:ok, Datatype.t()} | {:error, Refusal.t()}
  def resolve(ash_type, rdf_override \\ nil, storage_override \\ nil) do
    normalized = normalize_ash_type(ash_type)

    cond do
      is_binary(rdf_override) and absolute_iri?(rdf_override) ->
        {:ok,
         %Datatype{
           ash_type: ash_type,
           rdf_datatype: rdf_override,
           storage_type: storage_override || builtin_storage(normalized)
         }}

      is_binary(rdf_override) ->
        {:error,
         Refusal.new(
           :REFUSED_UNMAPPED_DATATYPE,
           ash_type,
           "explicit RDF datatype must be an absolute IRI",
           %{rdf_datatype: rdf_override}
         )}

      Map.has_key?(@builtins, normalized) ->
        {rdf_datatype, storage} = Map.fetch!(@builtins, normalized)

        {:ok,
         %Datatype{
           ash_type: ash_type,
           rdf_datatype: rdf_datatype,
           storage_type: storage_override || storage
         }}

      true ->
        {:error,
         Refusal.new(
           :UNSUPPORTED_ASH_TYPE,
           ash_type,
           "Ash type has no admitted RDF datatype contract; supply an explicit mapping",
           %{normalized_type: normalized}
         )}
    end
  end

  @spec supported?(term()) :: boolean()
  def supported?(ash_type), do: Map.has_key?(@builtins, normalize_ash_type(ash_type))

  @spec builtin_contracts() :: map()
  def builtin_contracts, do: @builtins

  defp builtin_storage(normalized) do
    case Map.get(@builtins, normalized) do
      {_rdf, storage} -> storage
      nil -> nil
    end
  end

  defp normalize_ash_type(type) when is_atom(type) do
    cond do
      Map.has_key?(@builtins, type) -> type
      true -> Map.get(@ash_type_modules, Atom.to_string(type), type)
    end
  end

  defp normalize_ash_type(type), do: type

  defp absolute_iri?(value) do
    case URI.parse(value) do
      %URI{scheme: scheme} when is_binary(scheme) and scheme != "" -> true
      _ -> false
    end
  end
end
