# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Domain.Verifier do
  @moduledoc """
  Verifies reference object maps across the resources of an `Ash.Domain`.
  """

  use Spark.Dsl.Verifier

  alias AshR2RML.Mapping
  alias Spark.Dsl.Verifier

  @impl true
  def verify(dsl) do
    domain = Verifier.get_persisted(dsl, :module)

    members =
      dsl
      |> Verifier.get_entities([:resources])
      |> Enum.map(& &1.resource)

    mappings =
      members
      |> Enum.flat_map(fn resource ->
        with true <- match?({:module, _}, Code.ensure_compiled(resource)),
             {:ok, %Mapping.Resource{} = mapping} <- AshR2RML.Resource.Info.mapping_result(resource) do
          [{resource, mapping}]
        else
          _ -> []
        end
      end)
      |> Map.new()

    errors = Enum.flat_map(mappings, fn {resource, mapping} -> check(resource, mapping, members, mappings) end)

    case errors do
      [] ->
        :ok

      [first | _] ->
        {:error,
         Spark.Error.DslError.exception(
           module: domain,
           path: [:resources],
           message: first
         )}
    end
  end

  @doc false
  @spec check(module(), Mapping.Resource.t(), [module()], map()) :: [String.t()]
  def check(resource, mapping, members, mappings) do
    Enum.flat_map(mapping.reference_object_maps, fn ref ->
      parent = ref.parent_resource
      label = "#{inspect(resource)}.#{inspect(ref.relationship)}"

      cond do
        parent not in members ->
          ["#{label}: parent resource #{inspect(parent)} is not in the domain"]

        not Map.has_key?(mappings, parent) ->
          ["#{label}: parent resource #{inspect(parent)} carries no R2RML mapping"]

        true ->
          parent_mapping = Map.fetch!(mappings, parent)
          subject_errors(label, parent, parent_mapping) ++ column_errors(label, parent, parent_mapping, ref)
      end
    end)
  end

  defp subject_errors(label, parent, %Mapping.Resource{subject_map: nil}),
    do: ["#{label}: parent #{inspect(parent)} has no subject map"]

  defp subject_errors(_label, _parent, _mapping), do: []

  defp column_errors(label, parent, parent_mapping, ref) do
    columns = known_columns(parent, parent_mapping)

    ref.joins
    |> Enum.map(& &1.parent)
    |> Enum.reject(&(to_string(&1) in columns))
    |> Enum.map(&"#{label}: parent join column #{inspect(&1)} does not exist on #{inspect(parent)}")
  end

  defp known_columns(parent, mapping) do
    attrs = parent |> Ash.Resource.Info.attributes() |> Enum.map(&to_string(&1.name))

    object_cols =
      for %{object_map: %{strategy: :column, value: v}} <- mapping.predicate_object_maps, do: to_string(v)

    subject_cols =
      case mapping.subject_map do
        %{strategy: :column, value: v} -> [to_string(v)]
        _ -> []
      end

    attrs ++ object_cols ++ subject_cols
  end
end
