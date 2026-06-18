# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Error.RequiresCypher25 do
  @moduledoc """
  Returned (never raised) when a Cypher 25 operation is attempted against a Neo4j
  server older than 2025.06. Upgrade to Neo4j 2025.06 or later to use this feature.
  """
  use Splode.Error, fields: [], class: :invalid

  def message(_), do: "This operation requires Cypher 25 (Neo4j ≥ 2025.06)"
end

defmodule AshNeo4j.Error.RequiresDynamicLabels do
  @moduledoc """
  Returned (never raised) when a dynamic label/type operation (`MATCH (n:$(expr))`,
  `-[r:$(expr)]->`) is attempted against a Neo4j server older than 5.26. This is
  the **server-feature axis** — dynamic labels run under plain `CYPHER 5` and are
  unrelated to the `CYPHER 25` selector (`AshNeo4j.Error.RequiresCypher25`).
  Upgrade to Neo4j 5.26 or later to use this feature.
  """
  use Splode.Error, fields: [], class: :invalid

  def message(_), do: "This operation requires dynamic labels (Neo4j ≥ 5.26)"
end

defmodule AshNeo4j.Error.UnsupportedChangesetFilter do
  @moduledoc """
  **Returned** (never raised) when a `changeset.filter` guard (the "only-update-if"
  predicate) can't be honoured (#361). We refuse rather than apply the write
  **unguarded**: silently dropping the guard would write when the predicate says
  not to (the write-side analogue of the traverse synthesis leaks, #342).

  Two cases today:

    * **update** — the guard doesn't reduce to a conjunction of supported attribute
      predicates (e.g. it contains `or`/`not`, a calculation, or a predicate the
      pushdown doesn't cover). Narrow it, or do the conditional update outside the
      data layer.
    * **destroy** — a filtered destroy is not supported yet (the `destroy_query`
      decision point is deferred); the whole guard is refused.
  """
  use Splode.Error, fields: [:resource, :filter], class: :invalid

  def message(%{resource: resource, filter: filter}) do
    "cannot honour the changeset filter guard on #{inspect(resource)} (#{inspect(filter)})"
  end
end

defmodule AshNeo4j.Error.UnsupportedAtomic do
  @moduledoc """
  **Returned** (never raised) when a `changeset.atomics` expression can't be
  rendered into the update Cypher `SET` (#361). The renderer covers arithmetic
  (`+ - * /`), comparisons, `if/3` (⇒ `CASE`), string concat / `string_trim`
  (Ash's string cast), attribute refs and scalar literals; an expression using any
  other Ash function is refused rather than mis-written.

  Express the change with supported operations, or perform it outside the data layer.
  """
  use Splode.Error, fields: [:resource, :expression], class: :invalid

  def message(%{resource: resource, expression: expression}) do
    "cannot render atomic update on #{inspect(resource)} into Cypher (#{inspect(expression)})"
  end
end

defmodule AshNeo4j.Error.GeoDimensionMismatch do
  @moduledoc """
  Returned (never raised) when a spatial operation combines geometries of
  different coordinate dimensions (2D vs 3D) — e.g. a 3D `%Geo.PointZ{}` against
  a 2D attribute, or vice versa. Neo4j silently returns `null` for mixed-CRS
  operations (which then drops rows in a `WHERE`), so AshNeo4j refuses up front
  (#270) by returning `{:error, error}`.

  Bridge worlds explicitly with a downward projection
  (`AshNeo4j.Geo.force_2d/1`) — collapse the 3D operand to its 2D footprint
  and evaluate in 2D. There is no implicit 2D→3D lift (a height cannot be
  fabricated).
  """
  use Splode.Error, fields: [:attr_dim, :value_dim], class: :invalid

  def message(%{attr_dim: attr_dim, value_dim: value_dim}) do
    "spatial dimension mismatch: a #{value_dim}D value against a #{attr_dim}D attribute. " <>
      "Project the 3D operand to 2D with AshNeo4j.Geo.force_2d/1 to evaluate in the 2D world, " <>
      "or use genuinely matching dimensions."
  end
end

defmodule AshNeo4j.Error.Unsupported3DGeometry do
  @moduledoc """
  Returned (never raised) when a 3D areal or linear geometry (`%Geo.PolygonZ{}`,
  `%Geo.LineStringZ{}`, …) is written. #270 Phase 1 supports 3D **points**
  (`%Geo.PointZ{}`) only; 3D areal/linear geometries are deferred to Phase 2,
  because exact 3D containment/distance needs a model the 2D `topo` refinement
  cannot provide. Storing 2D bbox companions would silently drop the z.
  """
  use Splode.Error, fields: [:geometry], class: :invalid

  def message(%{geometry: geometry}) do
    "#{inspect(geometry)} (3D areal/linear geometry) is not supported yet — #270 Phase 1 covers " <>
      "Geo.PointZ only. Use a 2D geometry, or project to 2D, until 3D areal support lands."
  end
end

defmodule AshNeo4j.Error.UnresolvableTraversal do
  @moduledoc """
  **Returned** (never raised) when a `traverse(^chain, …)` filter predicate can't
  be formed because the current graph view can't resolve part of it — a reached
  node whose label resolves to no loaded resource, or a field that isn't a
  mapped property of the reached resource.

  The filter-context counterpart to `AshNeo4j.Unknown` (the value-context
  "couldn't determine"): same `{world, reason, context}` shape. A data layer
  returns this as `{:error, error}` and never raises — `:reason` is a structural
  atom, `:context` is diagnostic.
  """
  use Splode.Error, fields: [:world, :reason, :context], class: :invalid

  def message(%{world: world, reason: reason, context: context}) do
    base = "cannot push down a traverse filter on #{inspect(world)} — #{reason}"
    if context in [nil, %{}], do: base, else: base <> " (#{inspect(context)})"
  end
end

defmodule AshNeo4j.Error.UnsupportedManyToMany do
  @moduledoc """
  **Returned** (never raised) when a relationship write resolves to a many-to-many
  modelled as **back-to-back `has_many`** — two resources each declaring a
  `has_many` to the other over one edge (#127). Ash anchors a `has_many` by an
  attribute on the *related* resource; with a `has_many` on both sides there is no
  to-one side to anchor the connect, so the data layer can't determine which node
  to relate. The edge itself already represents the many-to-many; the model just
  needs a to-one side on each hop to anchor the connect.

  Model many-to-many with a **joiner node** instead — two to-one (`belongs_to`)
  hops through a join resource (`Source →[E1] Join →[E2] Dest`); see the
  `Party → PlaceRef → Place` example. Native `many_to_many` is tracked in #370.
  """
  use Splode.Error, fields: [:resource, :related, :relationship], class: :invalid

  def message(%{resource: resource, related: related, relationship: relationship}) do
    "cannot relate #{inspect(resource)} to #{inspect(related)} via :#{relationship} — this is a " <>
      "many-to-many modelled as back-to-back has_many (a has_many on both sides of one edge), which " <>
      "leaves no to-one side to anchor the connect. Model it with a joiner node (two to-one hops " <>
      "through a join resource; see Party → PlaceRef → Place). Native many_to_many is tracked in #370."
  end
end

defmodule AshNeo4j.Error.Neo4j do
  @moduledoc """
  Wraps a Neo4j server error surfaced from `AshNeo4j.Cypher.run/1` (a
  `%Bolty.Error{}`), preserving its Neo4j status code and message and classifying
  it by `:category` (#358) — so a failure surfaces as the actual error, not a
  generic string. The server-side complement to the returned-error work (#350).

  `:category` is one of `:constraint` (a `ConstraintValidationFailed` — what
  `identities` / primary-key constraints rely on), `:transient` (retryable, e.g.
  a deadlock), `:statement` (a syntax/parameter error — our generated Cypher is
  wrong), `:security`, or `:other`.
  """
  use Splode.Error, fields: [:neo4j_code, :neo4j_message, :category], class: :invalid

  def message(%{neo4j_code: nil, neo4j_message: msg}), do: "Neo4j error: #{msg}"
  def message(%{neo4j_code: code, neo4j_message: nil}), do: "Neo4j #{code}"
  def message(%{neo4j_code: code, neo4j_message: msg}), do: "Neo4j #{code}: #{msg}"

  @doc """
  Maps an error surfaced from `Cypher.run/1` to a classified `AshNeo4j.Error.Neo4j`.
  A `%Bolty.Error{}` with a Neo4j status code is classified by that code; any
  other error term is wrapped with `category: :other`.
  """
  def from_bolt(%{bolt: %{code: code, message: msg}}) when is_binary(code) do
    exception(neo4j_code: code, neo4j_message: msg, category: category(code))
  end

  def from_bolt(%{__exception__: true} = error) do
    exception(neo4j_code: nil, neo4j_message: Exception.message(error), category: :other)
  end

  def from_bolt(other) do
    exception(neo4j_code: nil, neo4j_message: if(is_binary(other), do: other, else: inspect(other)), category: :other)
  end

  @doc "True for a Neo4j constraint-violation error (drives `identities` / PK constraints)."
  def constraint_violation?(%__MODULE__{category: :constraint}), do: true
  def constraint_violation?(_), do: false

  defp category("Neo.ClientError.Schema.ConstraintValidationFailed"), do: :constraint
  defp category("Neo.TransientError." <> _), do: :transient
  defp category("Neo.ClientError.Statement." <> _), do: :statement
  defp category("Neo.ClientError.Security." <> _), do: :security
  defp category(_), do: :other
end

