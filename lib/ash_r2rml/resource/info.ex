# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Resource.Info do
  @moduledoc "Public introspection over the normalized mapping IR."

  alias AshR2RML.Refusal

  @doc "The persisted mapping of a resource, or `nil` when it carries none."
  @spec mapping(module()) :: AshR2RML.Mapping.Resource.t() | nil
  def mapping(resource) do
    case mapping_result(resource) do
      {:ok, mapping} -> mapping
      {:error, _} -> nil
    end
  end

  @doc """
  The persisted mapping of a resource, or a typed refusal when the module carries none
  (plain Ash resources, non-Spark modules, resources without the extension).
  """
  @spec mapping_result(module()) ::
          {:ok, AshR2RML.Mapping.Resource.t()} | {:error, Refusal.t()}
  def mapping_result(resource) do
    case Spark.Dsl.Extension.get_persisted(resource, :ash_r2rml_public_mapping, nil) do
      %AshR2RML.Mapping.Resource{} = mapping -> {:ok, mapping}
      _ -> {:error, not_mapped(resource)}
    end
  rescue
    UndefinedFunctionError -> {:error, not_mapped(resource)}
    ArgumentError -> {:error, not_mapped(resource)}
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
  def fetch_mapping(resource) when is_atom(resource) and not is_nil(resource) do
    case mapping_result(resource) do
      {:ok, %AshR2RML.Mapping.Resource{} = mapping} -> {:ok, mapping}
      {:error, %Refusal{}} -> {:error, :not_mapped}
    end
  end

  def fetch_mapping(_), do: {:error, :not_mapped}

  @doc "The SPARQL query entities declared in the resource's `sparql` section."
  @spec sparql_queries(module()) :: [AshR2RML.Dsl.SparqlQuery.t()]
  def sparql_queries(resource) do
    Spark.Dsl.Extension.get_entities(resource, [:sparql])
  rescue
    UndefinedFunctionError -> []
  end
end
