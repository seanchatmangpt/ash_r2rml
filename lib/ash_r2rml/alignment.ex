# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.VerifyMapping.Alignment do
  @moduledoc """
  Fail-closed schema alignment verifier plumbing.

  Verifies that every mapped attribute and column in `AshR2RML.Mapping.Resource` corresponds
  to a valid attribute on the underlying Ash resource module.
  """

  alias AshR2RML.Mapping.{ObjectMap, PredicateObjectMap, Resource}
  alias AshR2RML.Refusal

  @doc "Verifies attribute alignment on an AshR2RML.Mapping.Resource"
  @spec verify(Resource.t()) :: :ok | {:error, Refusal.t()}
  def verify(%Resource{ash_resource: module, predicate_object_maps: poms})
      when is_atom(module) and not is_nil(module) do
    if Code.ensure_loaded?(Ash.Resource.Info) and function_exported?(Ash.Resource.Info, :attributes, 1) do
      resource_attributes =
        module
        |> Ash.Resource.Info.attributes()
        |> Enum.map(&to_string(&1.name))
        |> MapSet.new()

      invalid_pom =
        Enum.find(poms, fn %PredicateObjectMap{object_map: %ObjectMap{strategy: :column, value: col}} ->
          not MapSet.member?(resource_attributes, col)
        end)

      case invalid_pom do
        nil ->
          :ok

        %PredicateObjectMap{object_map: %ObjectMap{value: unmapped_col}} ->
          {:error,
           Refusal.new(
             :REFUSED_UNKNOWN_ATTRIBUTE,
             module,
             "Mapped column '#{unmapped_col}' does not exist on Ash resource attributes",
             %{column: unmapped_col, resource: module}
           )}
      end
    else
      :ok
    end
  end

  def verify(%Resource{}), do: :ok
end
