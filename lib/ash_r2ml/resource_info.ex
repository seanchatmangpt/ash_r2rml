# SPDX-FileCopyrightText: 2026 ash_r2ml contributors <https://github.com/seanchatmangpt/ash_r2ml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2ml.Resource.Info do
  @moduledoc "Introspection for the side-by-side R2RML semantic projection."

  alias AshR2ml.Mapping

  @spec mapped?(module()) :: boolean()
  def mapped?(resource), do: function_exported?(resource, :__ash_r2ml_mapping__, 0)

  @spec mapping(module()) :: Mapping.t() | nil
  def mapping(resource) do
    if mapped?(resource), do: resource.__ash_r2ml_mapping__(), else: nil
  end

  @spec mapping!(module()) :: Mapping.t()
  def mapping!(resource) do
    mapping(resource) ||
      raise ArgumentError,
            "#{inspect(resource)} has no AshR2ml mapping; add extensions: [AshR2ml] and an r2rml block"
  end

  @doc "Returns whether the existing AshNeo4j control mapping is also present."
  @spec neo4j_control_present?(module()) :: boolean()
  def neo4j_control_present?(resource),
    do: function_exported?(resource, :__ash_neo4j_mapping__, 0)
end
