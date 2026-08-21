# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Functions.GeofDistance do
  @moduledoc "GeoSPARQL geof:distance spatial distance expression."
  use Ash.Query.Function, name: :geof_distance

  @impl true
  def args, do: [:any, :any]

  @impl true
  def returns, do: :float
end

defmodule AshR2RML.Functions.GeofSfIntersects do
  @moduledoc "GeoSPARQL geof:sfIntersects spatial intersection boolean expression."
  use Ash.Query.Function, name: :geof_sf_intersects

  @impl true
  def args, do: [:any, :any]

  @impl true
  def returns, do: :boolean
end

defmodule AshR2RML.Functions.VecCosineSimilarity do
  @moduledoc "Vector similarity expression compiling to pgvector cosine distance."
  use Ash.Query.Function, name: :vec_cosine_similarity

  @impl true
  def args, do: [:any, :any]

  @impl true
  def returns, do: :float
end
