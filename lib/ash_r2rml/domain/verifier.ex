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

    mappings = Map.new(members, fn resource -> {resource, resolve(resource)} end)

    errors =
      Enum.flat_map(mappings, fn
        {resource, %Mapping.Resource{} = mapping} -> check(resource, mapping, members, mappings)
        {_resource, _failure} -> []
      end)

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

  # A member resolves to its mapping, or to the real failure (%Refusal{} or a
  # not-compiled marker) so the parent's own refusal is surfaced, not masked.
  defp resolve(resource) do
    case Code.ensure_compiled(resource) do
      {:module, _} ->
        case AshR2RML.Resource.Info.mapping_result(resource) do
          {:ok, %Mapping.Resource{} = mapping} -> mapping
          {:error, %AshR2RML.Refusal{} = refusal} -> refusal
        end

      {:error, reason} ->
        {:not_compiled, reason}
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

        true ->
          case Map.get(mappings, parent) do
            %Mapping.Resource{} = parent_mapping ->
              subject_errors(label, parent, parent_mapping) ++
                column_errors(label, resource, mapping, parent, parent_mapping, ref)

            nil ->
              ["#{label}: parent resource #{inspect(parent)} carries no R2RML mapping"]

            failure ->
              ["#{label}: parent resource #{inspect(parent)} failed to map: #{describe(failure)}"]
          end
      end
    end)
  end

  defp describe(%AshR2RML.Refusal{code: code, detail: detail}), do: "#{code}: #{detail}"
  defp describe({:not_compiled, reason}), do: "module could not be compiled (#{inspect(reason)})"
  defp describe(other), do: inspect(other)

  defp subject_errors(label, parent, %Mapping.Resource{subject_map: nil}),
    do: ["#{label}: parent #{inspect(parent)} has no subject map"]

  defp subject_errors(_label, _parent, _mapping), do: []

  defp column_errors(label, child, child_mapping, parent, parent_mapping, ref) do
    parent_columns = known_columns(parent, parent_mapping)
    child_columns = known_columns(child, child_mapping)

    parent_errors =
      ref.joins
      |> Enum.map(& &1.parent)
      |> Enum.reject(&(to_string(&1) in parent_columns))
      |> Enum.map(&"#{label}: parent join column #{inspect(&1)} does not exist on #{inspect(parent)}")

    child_errors =
      ref.joins
      |> Enum.map(& &1.child)
      |> Enum.reject(&(to_string(&1) in child_columns))
      |> Enum.map(&"#{label}: child join column #{inspect(&1)} does not exist on #{inspect(child)}")

    parent_errors ++ child_errors
  end

  # Join conditions carry SOURCE column names (attribute source || name).
  defp known_columns(resource, mapping) do
    attrs =
      resource
      |> Ash.Resource.Info.attributes()
      |> Enum.map(&to_string(&1.source || &1.name))

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
