# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Capability do
  @moduledoc """
  Capability probing of an Ash resource's data layer through `Ash.DataLayer.can?/2`.

  `AshR2RML.QueryBuilder` consults `probe/1` instead of naming data-layer modules, so a layer
  that cannot push a filter, sort, limit or offset down is read without that pushdown and never
  raises. The probe never raises either: a layer whose `can?/2` crashes or returns a non-boolean
  reports `false` for that feature.

  The one fact `can?/2` cannot express is string collation. `bytewise_string_order?/1` keeps an
  explicit allowlist (ETS and SQLite, whose default collation compares binaries bytewise) for
  that single question; Postgres collation is locale-dependent, so string ORDER BY is never
  pushed there. The SQLite module is named through `Module.concat/1`, so no data-layer
  reference exists at compile time.
  """

  @bytewise_collation_layers [Ash.DataLayer.Ets, Module.concat(["AshSqlite", "DataLayer"])]

  @type t :: %{
          filter: boolean(),
          sort: boolean(),
          limit: boolean(),
          offset: boolean(),
          join: boolean(),
          multitenancy: boolean(),
          transact: boolean()
        }

  @doc """
  Probes `resource`'s data layer.

  `join` asks whether the layer can join the resource to itself (`{:join, resource}`).
  """
  @spec probe(module()) :: t()
  def probe(resource) when is_atom(resource) do
    %{
      filter: can?(:filter, resource),
      sort: can?(:sort, resource),
      limit: can?(:limit, resource),
      offset: can?(:offset, resource),
      join: can?({:join, resource}, resource),
      multitenancy: can?(:multitenancy, resource),
      transact: can?(:transact, resource)
    }
  end

  @doc """
  True when ORDER BY over strings on `resource`'s data layer matches bytewise (SPARQL) order.

  This is an allowlist, not a probe: `Ash.DataLayer.can?/2` cannot express collation.
  """
  @spec bytewise_string_order?(module()) :: boolean()
  def bytewise_string_order?(resource) when is_atom(resource) do
    Ash.Resource.Info.data_layer(resource) in @bytewise_collation_layers
  rescue
    _ -> false
  end

  defp can?(feature, resource) do
    Ash.DataLayer.can?(feature, resource) == true
  rescue
    _ -> false
  end
end
