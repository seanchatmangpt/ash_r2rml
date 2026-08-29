# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Reactor.Steps.EvaluateDifferential do
  @moduledoc """
  Reactor step: SPARQL behavioral differential evaluation.

  When two or more `%AshR2RML.SPARQL.Observation{}` values are present, the step
  compares them through `AshR2RML.SPARQL.Differential`. The caller may provide a
  semantic subject in metadata under `:subject`; otherwise the receipt is scoped
  to the generic Reactor pipeline rather than inventing an application entity.
  """

  use Reactor.Step

  @impl Reactor.Step
  def run(%{observations: observations, metadata: metadata}, _context, _options) do
    if is_list(observations) and length(observations) >= 2 do
      metadata = metadata || %{}
      subject = Map.get(metadata, :subject, Map.get(metadata, "subject", :reactor_pipeline))
      AshR2RML.SPARQL.Differential.compare(subject, observations, metadata)
    else
      {:ok, nil}
    end
  end
end
