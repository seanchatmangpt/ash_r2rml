# SPDX-FileCopyrightText: 2026 ash_r2ml contributors <https://github.com/seanchatmangpt/ash_r2ml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2ML do
  @moduledoc """
  Semantic mapping compiler between Ash resources and W3C R2RML.

  AshR2ML is not an Ash data layer and never owns persistence. Ash-first and
  ontology-first inputs converge on `AshR2ML.Mapping.Bundle`; R2RML is then a
  deterministic projection of that normalized IR. RDF serialization and SPARQL
  execution remain explicit boundary choices rather than alternate sources of
  truth.
  """

  @doc "Compile one Ash resource into its normalized semantic mapping."
  defdelegate mapping(resource), to: AshR2ML.Resource.Info

  @doc "Compile one or more Ash resources, including mapped relationship targets, into a closed bundle."
  defdelegate compile(resources), to: AshR2ML.Compiler, as: :compile_resources

  @doc "Compile an admitted ontology/application-profile/SHACL projection into the same mapping bundle."
  defdelegate compile_profile(profile), to: AshR2ML.Compiler

  @doc "Parse RDF/Turtle + SHACL into the normalized closed ontology-first profile."
  def ingest_turtle(turtle, opts \\ []), do: AshR2ML.Ingestion.from_turtle(turtle, opts)

  @doc "Compile RDF/Turtle + SHACL into the same canonical mapping bundle as Ash-first resources."
  def compile_turtle(turtle, opts \\ []), do: AshR2ML.Ingestion.compile_turtle(turtle, opts)

  @doc "Parse JSON-LD 1.1 + SHACL into the normalized closed ontology-first profile."
  def ingest_jsonld(jsonld, opts \\ []), do: AshR2ML.Ingestion.from_jsonld(jsonld, opts)

  @doc "Compile JSON-LD 1.1 + SHACL into the same canonical mapping bundle as Turtle and Ash-first resources."
  def compile_jsonld(jsonld, opts \\ []), do: AshR2ML.Ingestion.compile_jsonld(jsonld, opts)

  @doc "Admit and identify a SPARQL query without executing it."
  defdelegate admit_sparql(query), to: AshR2ML.SPARQL.Query, as: :admit

  @doc "Explore all supplied lawful SPARQL execution candidates without prematurely selecting among them."
  def plan_sparql(query, opts \\ []), do: AshR2ML.SPARQL.explore(query, opts)

  @doc "Execute an explicitly selected or uniquely forced SPARQL execution plan."
  defdelegate execute_sparql(plan), to: AshR2ML.SPARQL, as: :execute

  @doc "Render standards-oriented R2RML Turtle from a bundle or Ash resource set."
  defdelegate render(resources_or_bundle), to: AshR2ML.R2RML
end
