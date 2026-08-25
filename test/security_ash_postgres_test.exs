# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.SecurityAshPostgresTest do
  @moduledoc """
  R2RML-105: end-to-end, compiled-resource-level coverage of `AshR2RML.Security.sanitize_mapping/2`'s
  `:postgres`-gated exclusion path, through the real compiler entrypoint
  (`AshR2RML.Compiler.compile_resources/1`) rather than by calling `Security.sanitize_mapping/2`
  directly on a hand-built mapping (that already exists in `test/obda_in_memory_test.exs` and is
  not what this ticket closes).

  Chicago-style: `AshPostgresFixture.MerchantAccount` (`test/support/ash_postgres_fixture/
  resources.ex`) is a real, compiled `Ash.Resource` genuinely backed by `AshPostgres.DataLayer`
  (not a mock or stand-in data layer) -- `Ash.Resource.Info.data_layer/1` returns the real
  `AshPostgres.DataLayer` module. No live PostgreSQL connection is started or required: Spark DSL
  compilation and `AshR2RML.Resource.Info.mapping_result/1` are pure introspection over the
  compiled module, and `AshR2RML.Compiler.compile_resources/1` never issues a query.
  """
  use ExUnit.Case, async: true

  alias AshPostgresFixture.MerchantAccount
  alias AshR2RML.Compiler

  test "compile_resources/1 removes the field-policy-protected attribute's predicate_object_map and records the exclusion" do
    # Confirms the fixture actually exercises the branch this ticket closes: a real
    # AshPostgres.DataLayer-backed resource, not the Ash.DataLayer.Ets fixtures used elsewhere.
    assert AshR2RML.DataLayer.backend(MerchantAccount) == :postgres

    assert {:ok, bundle} = Compiler.compile_resources([MerchantAccount])
    assert [mapping] = bundle.resources

    # AC3: the policied attribute's predicate_object_map is removed from the real compiler
    # entrypoint's output -- not merely absent from a hand-built mapping.
    refute Enum.any?(mapping.predicate_object_maps, &(&1.attribute == :secret_key))

    # AC3: the exclusion is recorded in mapping.metadata[:field_policy_excluded_attributes],
    # populated (non-empty) rather than silently dropped.
    excluded = mapping.metadata[:field_policy_excluded_attributes]
    assert is_list(excluded)
    assert :secret_key in excluded

    # Real, observed behavior, not assumed: :display_name also carries an explicit field_policy
    # (Ash requires full field coverage once any field_policies block exists -- see the fixture's
    # moduledoc), and AshR2RML.Security's `field_policy_protected?/2` does not distinguish an
    # unconditionally-granting `always()` policy from :secret_key's genuinely conditional one
    # (documented tradeoff, R2RML-106 WON'T FIX). Asserting the full, real state here rather than
    # only the single attribute AC3 names.
    assert :display_name in excluded
    assert mapping.predicate_object_maps == []
  end

  test "compile_resources/1 no-ops the exclusion on an Ash.DataLayer.Ets-backed resource in the same bundle" do
    # Confirms the :postgres gate is real and specific: mixing a postgres-backed resource
    # (excluded) with an ets-backed one (untouched) in a single compile_resources/1 call proves
    # the exclusion isn't a blanket behavior triggered by any field_policy anywhere in the run.
    alias AshR2RML.Fortune5.PaymentGateway

    assert AshR2RML.DataLayer.backend(PaymentGateway) == :ets

    assert {:ok, bundle} = Compiler.compile_resources([MerchantAccount, PaymentGateway])

    postgres_mapping = Enum.find(bundle.resources, &(&1.ash_resource == MerchantAccount))
    ets_mapping = Enum.find(bundle.resources, &(&1.ash_resource == PaymentGateway))

    assert postgres_mapping.predicate_object_maps == []
    assert :secret_key in postgres_mapping.metadata[:field_policy_excluded_attributes]

    # PaymentGateway is real Ash.DataLayer.Ets-backed and its own field policies exist purely to
    # exercise AshR2RML.OBDA.InMemory's real Ash.read!/2 enforcement -- sanitize_mapping/2 must
    # leave it structurally untouched.
    assert Enum.any?(ets_mapping.predicate_object_maps, &(&1.attribute == :secret_key))
    refute Map.has_key?(ets_mapping.metadata, :field_policy_excluded_attributes)
  end
end
