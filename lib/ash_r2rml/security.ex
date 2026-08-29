# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Security do
  @moduledoc """
  Closes a specific, demonstrated gap structurally rather than only documenting it: Ash field
  policies are enforced only on Ash-mediated reads (`AshR2RML.OBDA.InMemory` calling
  `Ash.read!/2`). Ontop connects to a relational data layer directly over JDBC and has no
  concept of an Ash actor at all, so a `field_policy`-protected attribute mapped into R2RML
  would be returned in full to any SPARQL caller once deployed -- confirmed against a live
  Postgres + Ontop stack, not assumed.

  `sanitize_mapping/2` is wired into `AshR2RML.Compiler.compile_resources/1` (the Ash-first
  compilation path over real, compiled Ash resource modules): on an `AshPostgres.DataLayer`-
  backed resource, any R2RML-mapped attribute that also carries an explicit `field_policy` is
  removed from the mapping *before* it can ever be rendered to R2RML or handed to Ontop -- the
  attribute is structurally absent from that path rather than merely refused-and-explained.
  The exclusion is recorded in `mapping.metadata[:field_policy_excluded_attributes]` so it
  stays auditable instead of silently invisible. `Ash.DataLayer.Ets`-backed resources are
  untouched, because `AshR2RML.OBDA.InMemory` already enforces field policies for real there.

  This does not attempt to distinguish an unconditionally-granting field policy
  (`authorize_if always()`) from a genuinely conditional one -- doing so would require
  inspecting Ash's internal check AST, which is fragile across Ash versions. Any explicit
  `field_policy` declared on an R2RML-mapped attribute is excluded, full stop: an over-broad
  exclusion costs the resource author one metadata entry to review; an under-broad one
  silently ships the exact vulnerability this module exists to close.
  """

  alias AshR2RML.Mapping.Resource

  @doc """
  Returns `mapping` unchanged unless `ash_resource` is `AshPostgres.DataLayer`-backed with
  R2RML-mapped attributes that also carry an explicit `field_policy` -- those attributes'
  `predicate_object_maps` are removed and the exclusion recorded in
  `mapping.metadata[:field_policy_excluded_attributes]`.
  """
  @spec sanitize_mapping(module(), Resource.t()) :: Resource.t()
  def sanitize_mapping(ash_resource, %Resource{} = mapping) when is_atom(ash_resource) do
    if AshR2RML.DataLayer.backend(ash_resource) == :postgres do
      ash_resource |> unenforceable_attributes(mapping) |> then(&remove_attributes(mapping, &1))
    else
      mapping
    end
  end

  @doc """
  Pure transform: removes `attributes`' `predicate_object_maps` from `mapping` and records the
  removal in `mapping.metadata[:field_policy_excluded_attributes]`. `[]` is a no-op returning
  `mapping` unchanged. Decoupled from the `AshPostgres.DataLayer` backend gate in
  `sanitize_mapping/2` so the exclusion behavior itself is directly testable without requiring
  an `AshPostgres.DataLayer`-backed fixture.
  """
  @spec remove_attributes(Resource.t(), [atom()]) :: Resource.t()
  def remove_attributes(%Resource{} = mapping, []), do: mapping

  def remove_attributes(%Resource{predicate_object_maps: predicate_object_maps} = mapping, attributes)
      when is_list(attributes) do
    kept = Enum.reject(predicate_object_maps, &(&1.attribute in attributes))

    %{
      mapping
      | predicate_object_maps: kept,
        metadata: Map.put(mapping.metadata, :field_policy_excluded_attributes, attributes)
    }
  end

  @doc """
  Returns the R2RML-mapped attributes on `ash_resource` that also carry an explicit Ash
  `field_policy`, independent of data layer -- `sanitize_mapping/2` gates the actual exclusion
  on `AshPostgres.DataLayer`. Exposed publicly so it can be verified directly against a
  resource's real field policies without needing an `AshPostgres.DataLayer`-backed fixture.
  """
  @spec unenforceable_attributes(module(), Resource.t()) :: [atom()]
  def unenforceable_attributes(ash_resource, %Resource{predicate_object_maps: predicate_object_maps}) do
    predicate_object_maps
    |> Enum.map(& &1.attribute)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.filter(&field_policy_protected?(ash_resource, &1))
  end

  defp field_policy_protected?(ash_resource, attribute) do
    Code.ensure_loaded?(Ash.Policy.Info) and
      match?([_ | _], Ash.Policy.Info.field_policies_for_field(ash_resource, attribute))
  rescue
    _ -> false
  end
end
