# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML do
  @moduledoc """
  Semantic mapping compiler between Ash resources and W3C R2RML.

  AshR2RML is not an Ash data layer and never owns persistence. Ash resources
  declare their mapping through the `AshR2RML.Resource` Spark extension (and
  optionally `AshR2RML.Domain`); that DSL compiles to `AshR2RML.Mapping.Bundle`,
  and R2RML is a deterministic projection of that normalized IR. RDF
  serialization and SPARQL execution remain explicit boundary choices rather
  than alternate sources of truth.

  This module is the thin public API only; it is not a Spark extension.

  ## Example

  Given resources that `use Ash.Resource, extensions: [AshR2RML]`:

      resources = [MyApp.Person, MyApp.Company]

      {:ok, bundle} = AshR2RML.compile(resources)
      {:ok, turtle} = AshR2RML.render(bundle)

      %AshR2RML.CompilationReceipt{status: :PARTIAL_ALIVE} =
        AshR2RML.validate(resources)

  Every function returns `{:error, %AshR2RML.Refusal{}}` (or a `:REFUSED`
  receipt) for input it cannot map; read the refusal's reason to see what to
  change in the resource.
  """

  alias AshR2RML.{Compiler, CompilationReceipt, Refusal}
  alias AshR2RML.Mapping.Bundle

  @doc """
  Compile one Ash resource into its normalized semantic mapping.

      mapping = AshR2RML.mapping(MyApp.Person)
  """
  defdelegate mapping(resource), to: AshR2RML.Resource.Info

  @doc """
  Compile one or more Ash resources into a closed bundle.

      {:ok, %AshR2RML.Mapping.Bundle{}} = AshR2RML.compile([MyApp.Person])
  """
  defdelegate compile(resources), to: AshR2RML.Compiler, as: :compile

  @doc """
  Inspect normalized AshR2RML resource mapping, returning a typed result
  instead of raising.

      result = AshR2RML.mapping_result(MyApp.Person)
  """
  defdelegate mapping_result(resource), to: AshR2RML.Resource.Info

  @doc """
  Render standards-oriented R2RML Turtle from a bundle or Ash resource set.

      {:ok, turtle} = AshR2RML.render([MyApp.Person])
  """
  defdelegate render(resources_or_bundle), to: AshR2RML.R2RML

  @doc """
  Alias of `render/1`, named for the format it produces.

      {:ok, turtle} = AshR2RML.render_r2rml([MyApp.Person])
  """
  defdelegate render_r2rml(resources_or_bundle), to: AshR2RML.R2RML, as: :render

  @doc """
  Validate resources and return a compilation receipt.

  Both compilation and rendering refusals become a `:REFUSED` receipt carrying
  the typed `AshR2RML.Refusal`; nothing is raised.

      case AshR2RML.validate([MyApp.Person]) do
        %AshR2RML.CompilationReceipt{status: :PARTIAL_ALIVE} -> :mapped
        %AshR2RML.CompilationReceipt{status: :REFUSED, refusals: refusals} -> {:refused, refusals}
      end
  """
  @spec validate(term()) :: CompilationReceipt.t()
  def validate(resources) do
    with {:ok, %Bundle{} = bundle} <- Compiler.compile(resources),
         {:ok, r2rml} <- AshR2RML.R2RML.render(bundle) do
      %CompilationReceipt{
        status: :PARTIAL_ALIVE,
        standing: :constructed_not_actuated,
        mapping_sha256: Compiler.sha256(bundle),
        r2rml_sha256: Compiler.sha256(r2rml),
        query_parity: :UNKNOWN,
        cutover_authority: :UNAUTHORIZED,
        classes_admitted: length(bundle.resources),
        executed: [:canonical_mapping_ir, :r2rml_render],
        verified: [:canonical_mapping_ir_projection],
        blocked: [:sparql_sql_behavioral_parity, :cutover_authority],
        refusals: []
      }
    else
      {:error, %Refusal{} = refusal} ->
        %CompilationReceipt{
          status: :REFUSED,
          standing: :no_cutover,
          refusals: [refusal]
        }
    end
  end
end

defmodule AshR2RML.Validation do
  @moduledoc false
  defdelegate cutover_ready?(receipt), to: AshR2RML.Compiler
end
