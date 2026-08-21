# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GrandExample.SubReactors.InputVerifier do
  @moduledoc """
  Sub-Reactor composed inside the Grand Publishing Reactor for testing compose step integration.
  """
  use Reactor

  input :resources

  step :validate_resource_list do
    argument :resources, input(:resources)

    run fn %{resources: resources}, _ctx ->
      cond do
        not is_list(resources) or Enum.empty?(resources) ->
          {:error, "Resources input must be a non-empty list of modules"}

        Enum.all?(resources, &is_atom/1) ->
          {:ok, %{resource_count: length(resources), valid?: true}}

        true ->
          {:error, "All entries in resources list must be atom module names"}
      end
    end
  end

  return :validate_resource_list
end
