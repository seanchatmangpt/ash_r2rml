# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Reactor.Steps.VerifyAlignment do
  @moduledoc """
  Reactor step: fail-closed schema alignment verification.

  Runs `AshR2RML.VerifyMapping.Alignment.verify/1` over every resource in the
  `AshR2RML.Mapping.Bundle`.  Returns `{:ok, bundle}` when all verifications
  pass, or `{:error, refusal}` on the first failure.

  ## Arguments

  - `:bundle` — `%AshR2RML.Mapping.Bundle{}` produced by the compile step.
  """

  use Reactor.Step

  @impl Reactor.Step
  def run(%{bundle: bundle}, _context, _options) do
    resources = bundle.resources || []

    results = Enum.map(resources, &AshR2RML.VerifyMapping.Alignment.verify/1)

    case Enum.find(results, &match?({:error, _}, &1)) do
      {:error, refusal} -> {:error, refusal}
      nil -> {:ok, bundle}
    end
  end
end
