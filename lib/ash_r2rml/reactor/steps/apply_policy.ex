# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Reactor.Steps.ApplyPolicy do
  @moduledoc """
  Reactor step: apply actor-scoped Ash policy filtering to the mapping bundle.

  When `actor` is `nil` the bundle passes through unchanged.  Otherwise
  `AshR2RML.Policy.filter_for_actor/3` is called, which omits predicate-object
  maps and reference-object maps the actor is not authorized to read.

  ## Arguments

  - `:bundle` — `%AshR2RML.Mapping.Bundle{}` enriched with provenance maps.
  - `:actor` — optional actor map; `nil` disables filtering.
  """

  use Reactor.Step

  @impl Reactor.Step
  def run(%{bundle: bundle, actor: nil}, _context, _options) do
    {:ok, bundle}
  end

  def run(%{bundle: bundle, actor: actor}, _context, _options) do
    {:ok, AshR2RML.Policy.filter_for_actor(bundle, actor, [])}
  end
end
