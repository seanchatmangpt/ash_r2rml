# SPDX-FileCopyrightText: 2026 ash_r2ml contributors <https://github.com/seanchatmangpt/ash_r2ml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2ML.Ingestion do
  @moduledoc """
  Public RDF/SHACL ingestion boundary.

  Parsing and SHACL closure are implemented by the ontology-first migration
  compiler, then lowered into the same canonical `AshR2ML.Mapping.Bundle` used
  by Ash-first compilation. This keeps the public mapping IR as the convergence
  point without duplicating RDF parsing logic.
  """

  @spec from_turtle(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def from_turtle(turtle, opts \\ []), do: AshR2ml.Ingestion.from_turtle(turtle, opts)

  @spec compile_turtle(String.t(), keyword()) ::
          {:ok, AshR2ML.Mapping.Bundle.t()} | {:error, term()}
  def compile_turtle(turtle, opts \\ []) do
    with {:ok, profile} <- from_turtle(turtle, opts) do
      AshR2ML.Compiler.compile_profile(profile)
    end
  end
end

defmodule AshR2ML.OBDA.Ontop do
  @moduledoc "Public operator-invoked Ontop adapter."

  @type observation :: AshR2ml.OBDA.Observation.t()

  defdelegate command(opts), to: AshR2ml.OBDA.Ontop
  defdelegate query(opts), to: AshR2ml.OBDA.Ontop
  def query(opts, runner), do: AshR2ml.OBDA.Ontop.query(opts, runner)
  defdelegate parse_csv(output), to: AshR2ml.OBDA.Ontop
end

defmodule AshR2ML.Ggen do
  @moduledoc "Public ggen manufacturing facade over the ontology-first compiler."

  defdelegate compile_bundle(profile), to: AshR2ml.Ggen
  def compile_turtle_bundle(turtle, opts \\ []), do: AshR2ml.Ggen.compile_turtle_bundle(turtle, opts)
end
