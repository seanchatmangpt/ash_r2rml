# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.FollowupContextMultitenancyTest do
  @moduledoc """
  Under `:context` multitenancy the same primary key exists in every tenant schema, so a
  subject template built only from the primary key is not a globally unique identity and is
  refused at compile time. Asserted through `Introspection` and `Mapping.validate/1` over
  real resources, never by evaluating a module that would emit Spark warnings.
  Lane B5 implements the hardening; the refusal assertions fail until it lands.
  """

  use ExUnit.Case, async: true

  alias AshR2RML.Followup.{ContextBare, ContextGlobal}
  alias AshR2RML.Introspection
  alias AshR2RML.Mapping
  alias AshR2RML.Mapping.{LogicalTable, Resource, SubjectMap}

  defp mapping(resource, template) do
    %Resource{
      ash_resource: resource,
      logical_table: %LogicalTable{table_name: "context_rows"},
      subject_map: %SubjectMap{strategy: :template, value: template, term_type: :iri},
      predicate_object_maps: [],
      identities: Introspection.identities(resource)
    }
  end

  test "primary key is not a globally unique identity under :context multitenancy" do
    assert Introspection.identities(ContextBare) == []
    refute Introspection.stable_subject_identity?(ContextBare, ["id"])
  end

  test "primary-key-only subject template is refused as a non-unique identity" do
    assert {:error, refusals} = Mapping.validate(mapping(ContextBare, "urn:uuid:{id}"))
    assert Enum.any?(refusals, &(&1.code == :REFUSED_NON_UNIQUE_SEMANTIC_IDENTITY))
  end

  test "positive control: an all_tenants?: true identity keeps its subject template stable" do
    assert Introspection.identities(ContextGlobal) == [[:code]]
    assert Introspection.stable_subject_identity?(ContextGlobal, ["code"])
    refute Introspection.stable_subject_identity?(ContextGlobal, ["id"])

    result = Mapping.validate(mapping(ContextGlobal, "urn:uuid:{code}"))

    refusals = if match?({:error, _}, result), do: elem(result, 1), else: []
    refute Enum.any?(refusals, &(&1.code == :REFUSED_NON_UNIQUE_SEMANTIC_IDENTITY))
  end
end
