# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Reactor.Steps.EvaluateDifferential do
  @moduledoc """
  Reactor step: SPARQL behavioral differential evaluation.

  When two or more `%AshR2RML.SPARQL.Observation{}` structs are present in
  `:observations`, calls `AshR2RML.SPARQL.Differential.compare/3` to verify
  parity across execution strategies.  Returns `{:ok, nil}` when insufficient
  observations are supplied (< 2).

  This step is non-retryable (`max_retries 0` in the pipeline DSL).

  ## Arguments

  - `:observations` — list of `%AshR2RML.SPARQL.Observation{}` structs (may be empty or nil).
  - `:metadata` — optional map forwarded to the differential evaluator.
  """

  use Reactor.Step

  @impl Reactor.Step
  def run(%{observations: obs, metadata: meta}, _context, _options) do
    if is_list(obs) and length(obs) >= 2 do
      AshR2RML.SPARQL.Differential.compare("PipelineSubject", obs, meta || %{})
    else
      {:ok, nil}
    end
  end
end
