# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.QueryBuilder.Pushdown do
  @moduledoc """
  A lowered SPARQL SELECT: the root resource, its mapping and the `AshR2RML.QueryBuilder.Plan`
  to read it with, plus the data `AshR2RML.QueryBuilder.Verification.verify/3` needs when the
  plan carries a limit.

  `keep` is `offset + limit` and `fetch` is `keep + 1` (the extra row is a tie sentinel); both
  are `nil` when the plan has no limit.
  """

  alias AshR2RML.Mapping.Resource
  alias AshR2RML.QueryBuilder.Plan

  @enforce_keys [:resource, :mapping, :plan]
  defstruct [:resource, :mapping, :plan, :keep, :fetch, keys: []]

  @type t :: %__MODULE__{
          resource: module(),
          mapping: Resource.t(),
          plan: Plan.t(),
          keep: pos_integer() | nil,
          fetch: pos_integer() | nil,
          keys: [map()]
        }

  @doc """
  The value of the `:query_pushdown` read option understood by `AshR2RML.OBDA.InMemory`.

  Only the spec whose `ash_resource == resource` is read through
  `AshR2RML.QueryBuilder.pushdown_query/4`; every other spec reads as before.
  """
  @spec read_option(t()) :: %{resource: module(), mapping: Resource.t(), plan: Plan.t()}
  def read_option(%__MODULE__{resource: resource, mapping: mapping, plan: plan}),
    do: %{resource: resource, mapping: mapping, plan: plan}
end
