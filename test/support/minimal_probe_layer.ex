# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Test.MinimalProbeLayer do
  @moduledoc """
  Hand-written minimal Ash data layer for capability tests: it can only `:read`, and answers
  `false` to every pushdown feature (filter, sort, limit, offset, join, multitenancy, transact).
  """

  use Spark.Dsl.Extension, transformers: [], sections: []

  @doc false
  def can?(_resource, :read), do: true
  def can?(_resource, _feature), do: false
end

defmodule AshR2RML.Test.MinimalProbeResource do
  @moduledoc false
  use Ash.Resource, domain: nil, data_layer: AshR2RML.Test.MinimalProbeLayer

  actions do
    defaults [:read]
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end
end
