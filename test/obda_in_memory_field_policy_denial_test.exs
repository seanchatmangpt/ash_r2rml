# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OBDA.InMemoryFieldPolicyDenialTest do
  @moduledoc """
  Field-policy denial through the sole runtime OBDA backend: an actor without the admin role
  gets rows for permitted attributes, and the policy-protected `secret_key` triple is absent
  from SPARQL results. An admin actor sees it, proving the omission is policy-driven.
  """
  use ExUnit.Case, async: false

  alias AshR2RML.Fortune5.PaymentGateway
  alias AshR2RML.OBDA.InMemory

  @secret "sk_live_must_not_leak"
  @secret_pred "https://w3id.org/fortune5/ontology#apiKeySecret"
  @name_pred "https://schema.org/name"

  setup do
    PaymentGateway
    |> Ash.Changeset.for_create(
      :create,
      %{name: "Gateway-Denial", provider: "p", api_endpoint: "https://x.example", secret_key: @secret},
      authorize?: false
    )
    |> Ash.create!(authorize?: false)

    :ok
  end

  defp run(actor, predicate) do
    InMemory.query(
      PaymentGateway,
      AshR2RML.mapping(PaymentGateway),
      "SELECT ?v WHERE { ?s <#{predicate}> ?v }",
      actor: actor
    )
  end

  test "non-admin actor: permitted attribute present, secret_key omitted" do
    actor = %{role: :user}

    assert {:ok, name_obs} = run(actor, @name_pred)
    assert name_obs.rows != []

    assert {:ok, secret_obs} = run(actor, @secret_pred)
    assert secret_obs.rows == []
    refute inspect(secret_obs) =~ @secret
  end

  test "admin actor sees secret_key (omission is policy-driven)" do
    assert {:ok, obs} = run(%{role: :admin}, @secret_pred)
    assert inspect(obs) =~ @secret
  end
end
