# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Datatype.Registry do
  @moduledoc """
  Loss-aware built-in and custom datatype correspondence.

  Unknown Ash types are never stringified implicitly. Custom semantic types are
  admitted as RDF datatypes only when their `AshR2RML.Type` contract is
  explicitly `:literal`; IRI, concept, value-object, and resource semantics must
  take their own R2RML term-map/resource path.
  """

  alias AshR2RML.Mapping.Datatype
  alias AshR2RML.Refusal

  @xsd "http://www.w3.org/2001/XMLSchema#"
  @ogc_geo "http://www.opengis.net/ont/geosparql#"

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
    atom: {@xsd <> "string", :text},
    geo_wkt: {@ogc_geo <> "wktLiteral", :geometry},
    vector: {@xsd <> "string", :vector},
    array: {@xsd <> "string", :array},
    duration: {@xsd <> "duration", :duration},
    uuid_v7: {@xsd <> "string", :uuid},
    module: {@xsd <> "string", :text}
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
    "Elixir.Ash.Type.DateTime" => :utc_datetime_usec,
    "Elixir.Ash.Type.NaiveDatetime" => :naive_datetime,
    "Elixir.Ash.Type.NaiveDatetimeUsec" => :naive_datetime_usec,
    "Elixir.Ash.Type.UUID" => :uuid,
    "Elixir.Ash.Type.CiString" => :ci_string,
    "Elixir.Ash.Type.Atom" => :atom,
    "Elixir.AshGeo.Geometry" => :geo_wkt,
    "Elixir.AshGeo.Point" => :geo_wkt,
    "Elixir.Ash.Type.Vector" => :vector,
    "Elixir.Ash.Type.Duration" => :duration,
    "Elixir.Ash.Type.UUIDv7" => :uuid_v7,
    "Elixir.Ash.Type.Module" => :module
  }

  @max_unwrap_depth 16

  @doc """
  Resolves an Ash type to an RDF datatype and storage type.

  Pipeline: unwrap NewTypes, normalize to a builtin key, then look up the first
  matching contract (explicit override, semantic literal, enum, money, builtin).
  Anything else is a typed `Refusal`, never an implicit string.
  """
  @spec resolve(term(), String.t() | nil, term() | nil) :: {:ok, Datatype.t()} | {:error, Refusal.t()}
  def resolve(ash_type, rdf_override \\ nil, storage_override \\ nil)

  def resolve({:array, inner} = ash_type, _rdf_override, _storage_override) do
    {:error,
     Refusal.new(
       :UNSUPPORTED_ASH_TYPE,
       ash_type,
       "array-typed attributes have no single-column RDF literal mapping; map the elements through a dedicated relationship or an explicit datatype on a scalar attribute",
       %{normalized_type: :array, inner_type: inner}
     )}
  end

  def resolve(ash_type, rdf_override, storage_override) do
    case unwrap_checked(ash_type) do
      {:ok, base, _constraints} -> resolve_base(ash_type, base, rdf_override, storage_override)
      {:error, %Refusal{}} = error -> error
    end
  end

  defp resolve_base(ash_type, base, rdf_override, storage_override) do
    normalized = normalize(base)

    with {:ok, rdf_datatype, default_storage} <-
           lookup_contract(ash_type, base, normalized, rdf_override) do
      {:ok,
       %Datatype{
         ash_type: ash_type,
         rdf_datatype: rdf_datatype,
         storage_type: storage_override || default_storage
       }}
    end
  end

  # First matching contract wins: explicit override, semantic literal,
  # non-literal refusal, enum, money, builtin table.
  # Returns `{:ok, rdf_datatype, default_storage_type}` or a typed refusal.
  defp lookup_contract(ash_type, _base, normalized, rdf_override) when is_binary(rdf_override) do
    if absolute_iri?(rdf_override) do
      {:ok, rdf_override, builtin_storage(normalized)}
    else
      {:error,
       Refusal.new(:REFUSED_UNMAPPED_DATATYPE, ash_type, "explicit RDF datatype must be an absolute IRI", %{
         rdf_datatype: rdf_override
       })}
    end
  end

  defp lookup_contract(ash_type, base, normalized, _rdf_override) do
    case semantic_contract(ash_type, base) do
      {:literal, datatype} = contract ->
        if semantic_literal?(contract),
          do: {:ok, datatype, semantic_storage(ash_type) || :text},
          else: builtin_contract(ash_type, base, normalized)

      {:non_literal, semantic_kind} ->
        {:error,
         Refusal.new(
           :REFUSED_NON_LITERAL_DATATYPE,
           ash_type,
           "non-literal semantic Ash type cannot be compiled as an RDF datatype",
           %{semantic_kind: semantic_kind}
         )}

      :none ->
        builtin_contract(ash_type, base, normalized)
    end
  end

  defp builtin_contract(ash_type, base, normalized) do
    cond do
      enum_type?(base) ->
        {:ok, @xsd <> "string", :text}

      AshR2RML.Money.money_type?(base) ->
        {:ok, @xsd <> "decimal", :decimal}

      Map.has_key?(@builtins, normalized) ->
        {rdf_datatype, storage} = Map.fetch!(@builtins, normalized)
        {:ok, rdf_datatype, storage}

      true ->
        {:error,
         Refusal.new(
           :UNSUPPORTED_ASH_TYPE,
           ash_type,
           "Ash type has no admitted RDF datatype contract; supply an explicit mapping or implement a literal AshR2RML.Type",
           %{normalized_type: normalized}
         )}
    end
  end

  @doc "True when `resolve/1` admits `ash_type` without overrides."
  @spec supported?(term()) :: boolean()
  def supported?(ash_type), do: match?({:ok, _}, resolve(ash_type))

  @doc """
  Recursively unwraps `Ash.Type.NewType` modules to their base type, merging
  constraints (outer constraints win over `subtype_constraints/0` of each layer).

  Returns `{base_type, constraints}`. Non-NewType input is returned unchanged.
  Raises `ArgumentError` on a NewType cycle or excessive nesting; use
  `unwrap_checked/2` for a typed refusal instead.
  """
  @spec unwrap(term(), keyword()) :: {term(), keyword()}
  def unwrap(type, constraints \\ []) do
    case unwrap_checked(type, constraints) do
      {:ok, base, merged} -> {base, merged}
      {:error, %Refusal{detail: detail}} -> raise ArgumentError, detail
    end
  end

  @doc """
  Like `unwrap/2` but a NewType cycle (or nesting deeper than #{@max_unwrap_depth})
  is a typed `UNSUPPORTED_ASH_TYPE` refusal.
  """
  @spec unwrap_checked(term(), keyword()) :: {:ok, term(), keyword()} | {:error, Refusal.t()}
  def unwrap_checked(type, constraints \\ []), do: do_unwrap(type, constraints, [])

  defp do_unwrap(type, constraints, seen) when is_atom(type) and not is_nil(type) do
    resolved = Ash.Type.get_type(type)

    cond do
      not new_type?(resolved) ->
        {:ok, resolved, constraints}

      resolved in seen or length(seen) >= @max_unwrap_depth ->
        {:error,
         Refusal.new(
           :UNSUPPORTED_ASH_TYPE,
           type,
           "NewType unwrapping cycles or nests deeper than #{@max_unwrap_depth} layers",
           %{normalized_type: :newtype_cycle}
         )}

      true ->
        inner = Keyword.merge(subtype_constraints(resolved), constraints)
        do_unwrap(resolved.subtype_of(), inner, [resolved | seen])
    end
  end

  defp do_unwrap(type, constraints, _seen), do: {:ok, type, constraints}

  defp subtype_constraints(module) do
    if function_exported?(module, :subtype_constraints, 0), do: module.subtype_constraints() || [], else: []
  end

  @doc "The builtin table: normalized type key to `{rdf_datatype, storage_type}`."
  @spec builtin_contracts() :: map()
  def builtin_contracts, do: @builtins

  # The declared type's own contract wins; otherwise the unwrapped base type's.
  defp semantic_contract(ash_type, base) do
    case contract_of(ash_type) do
      :none -> contract_of(base)
      found -> found
    end
  end

  defp contract_of(type) when is_atom(type) and not is_nil(type) do
    case AshR2RML.Type.contract(type) do
      {:ok, %{semantic_kind: :literal, datatype_iri: datatype}} -> {:literal, datatype}
      {:ok, %{semantic_kind: kind}} -> {:non_literal, kind}
      :error -> :none
    end
  end

  defp contract_of(_), do: :none

  defp semantic_literal?({:literal, datatype}), do: is_binary(datatype) and absolute_iri?(datatype)

  defp semantic_storage(ash_type) do
    if is_atom(ash_type) and not is_nil(ash_type) and Code.ensure_loaded?(ash_type) and
         function_exported?(ash_type, :storage_type, 1) do
      ash_type.storage_type([])
    end
  end

  defp enum_type?(ash_type) do
    is_atom(ash_type) and Code.ensure_loaded?(ash_type) and function_exported?(ash_type, :values, 0) and
      (Spark.implements_behaviour?(ash_type, Ash.Type.Enum) or function_exported?(ash_type, :storage_type, 0))
  end

  defp builtin_storage(normalized) do
    case Map.get(@builtins, normalized) do
      {_rdf, storage} -> storage
      nil -> nil
    end
  end

  # `base` is already NewType-unwrapped and `Ash.Type.get_type/1`-resolved.
  defp normalize(base) when is_atom(base) and not is_nil(base) do
    if Map.has_key?(@builtins, base) do
      base
    else
      Map.get(@ash_type_modules, Atom.to_string(base), base)
    end
  end

  defp normalize(base), do: base

  defp new_type?(module) do
    is_atom(module) and not is_nil(module) and Code.ensure_loaded?(module) and
      function_exported?(module, :subtype_of, 0) and Ash.Type.NewType.new_type?(module)
  end

  defp absolute_iri?(value) do
    case URI.parse(value) do
      %URI{scheme: scheme} when is_binary(scheme) and scheme != "" -> true
      _ -> false
    end
  end
end
