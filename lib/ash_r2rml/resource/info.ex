# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Resource.Info do
  @moduledoc "Public introspection over the normalized mapping IR."

  alias AshR2RML.Refusal

  @doc "The persisted mapping of a resource, or `nil` when it carries none."
  @spec mapping(module()) :: AshR2RML.Mapping.Resource.t() | nil
  def mapping(resource) do
    if loadable?(resource) do
      case mapping_result(resource) do
        {:ok, mapping} -> mapping
        {:error, _} -> nil
      end
    end
  end

  @doc """
  The persisted mapping of a resource, or a typed refusal when the loaded module carries none
  (plain Ash resources, non-Spark modules, resources without the extension).

  A module that cannot be loaded (never compiled, not a module) is never reported as unmapped:
  it refuses with `:REFUSED_INVALID_OPTION` and `evidence.reason == :module_unavailable`.
  """
  @spec mapping_result(module()) ::
          {:ok, AshR2RML.Mapping.Resource.t()} | {:error, Refusal.t()}
  def mapping_result(resource) do
    cond do
      not loadable?(resource) ->
        {:error, unavailable(resource)}

      function_exported?(resource, :spark_dsl_config, 0) ->
        case Spark.Dsl.Extension.get_persisted(resource, :ash_r2rml_public_mapping, nil) do
          %AshR2RML.Mapping.Resource{} = mapping -> {:ok, mapping}
          _ -> {:error, not_mapped(resource)}
        end

      true ->
        {:error, not_mapped(resource)}
    end
  end

  @doc "True when `module` is an atom that is loaded or loadable."
  @spec loadable?(term()) :: boolean()
  def loadable?(module) when is_atom(module) and not is_nil(module), do: Code.ensure_loaded?(module)
  def loadable?(_), do: false

  defp unavailable(resource) do
    Refusal.new(
      :REFUSED_INVALID_OPTION,
      resource,
      "#{inspect(resource)} is not a loadable module",
      %{option: :resource, reason: :module_unavailable}
    )
  end

  defp not_mapped(resource) do
    Refusal.new(
      :REFUSED_MISSING_SUBJECT_MAP,
      resource,
      "resource does not carry the AshR2RML extension mapping"
    )
  end

  @doc "The persisted mapping of a resource; raises `ArgumentError` when it carries none."
  @spec mapping!(module()) :: AshR2RML.Mapping.Resource.t()
  def mapping!(resource) do
    case mapping_result(resource) do
      {:ok, mapping} -> mapping
      {:error, refusal} -> raise ArgumentError, "#{refusal.code}: #{refusal.detail}"
    end
  end

  @doc "Resources of an Ash domain that carry the AshR2RML extension."
  @spec domain_resources(module()) :: [module()]
  def domain_resources(domain) do
    domain
    |> Ash.Domain.Info.resources()
    |> Enum.filter(fn resource ->
      extensions = Spark.extensions(resource)
      AshR2RML in extensions or AshR2RML.Resource in extensions
    end)
  end

  @doc "True when the module carries a mapping. Never raises, including on plain Ash resources."
  @spec mapped?(term()) :: boolean()
  def mapped?(resource), do: match?({:ok, _}, fetch_mapping(resource))

  @doc """
  Fetches the mapping for a module without raising.

  Plain Ash resources, non-Spark modules, and non-atoms yield `{:error, :not_mapped}`.
  """
  @spec fetch_mapping(term()) :: {:ok, AshR2RML.Mapping.Resource.t()} | {:error, :not_mapped}
  def fetch_mapping(resource) do
    if loadable?(resource) do
      case mapping_result(resource) do
        {:ok, %AshR2RML.Mapping.Resource{} = mapping} -> {:ok, mapping}
        {:error, %Refusal{}} -> {:error, :not_mapped}
      end
    else
      {:error, :not_mapped}
    end
  end

  @doc "The SPARQL query entities declared in the resource's `sparql` section."
  @spec sparql_queries(module()) :: [AshR2RML.Dsl.SparqlQuery.t()]
  def sparql_queries(resource) do
    cond do
      not loadable?(resource) -> raise ArgumentError, "#{inspect(resource)} is not a loadable module"
      function_exported?(resource, :spark_dsl_config, 0) -> Spark.Dsl.Extension.get_entities(resource, [:sparql])
      true -> []
    end
  end
end
