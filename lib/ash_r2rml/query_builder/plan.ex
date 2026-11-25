# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.QueryBuilder.Plan do
  @moduledoc """
  Query plan consumed by `AshR2RML.QueryBuilder.build_ash_query/3`.

  Filter grammar (all attribute names are atoms):

    * `{op, attribute, value}` with `op` in `:eq | :neq | :lt | :lte | :gt | :gte |
      :contains | :strstarts | :strends`
    * `{:not_nil, attribute, nil}` (attribute is not null)
    * `{:and, [filter]}` / `{:or, [filter]}`
    * `nil` (no filter)

  `sort` is a list of `{attribute, :asc | :desc}`.
  """

  defstruct needed_attributes: [],
            needed_relationships: [],
            filter: nil,
            sort: [],
            offset: 0,
            limit: nil

  @type op :: :eq | :neq | :lt | :lte | :gt | :gte | :contains | :strstarts | :strends | :not_nil
  @type filter ::
          nil
          | {op(), atom(), term()}
          | {:and, [filter()]}
          | {:or, [filter()]}

  @type t :: %__MODULE__{
          needed_attributes: [atom()],
          needed_relationships: [atom()],
          filter: filter(),
          sort: [{atom(), :asc | :desc}],
          offset: non_neg_integer(),
          limit: pos_integer() | nil
        }
end
