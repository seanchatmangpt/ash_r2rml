# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Reactor.Steps.AttachProvenance do
  @moduledoc """
  Reactor step: attach W3C PROV-O provenance predicate-object maps.

  Applies both `prov:generatedAtTime` (bound to the `:updated_at` column) and
  `prov:wasDerivedFrom` (bound to an IRI template) to every resource in the
  bundle.  Pure transformation; no compensate or undo needed.

  ## Arguments

  - `:bundle` — `%AshR2RML.Mapping.Bundle{}` that has passed alignment verification.
  """

  use Reactor.Step

  @impl Reactor.Step
  def run(%{bundle: bundle}, _context, _options) do
    updated_resources =
      Enum.map(bundle.resources || [], fn res ->
        res
        |> AshR2RML.Mapping.Provenance.attach_generated_at_time(:updated_at)
        |> AshR2RML.Mapping.Provenance.attach_was_derived_from("https://example.org/prov/source/{id}")
      end)

    {:ok, %{bundle | resources: updated_resources}}
  end
end
