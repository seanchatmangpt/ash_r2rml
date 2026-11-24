# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OBDA.PreflightTest do
  @moduledoc "Preflight over real policy + ETS + multitenant Ash resources."

  use ExUnit.Case, async: true

  alias AshR2RML.OBDA.Preflight
  alias AshR2RML.Refusal

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.OBDA.PreflightTest.Guarded
      resource AshR2RML.OBDA.PreflightTest.AttrTenant
      resource AshR2RML.OBDA.PreflightTest.GlobalTenant
      resource AshR2RML.OBDA.PreflightTest.Plain
    end
  end

  defmodule Guarded do
    use Ash.Resource,
      domain: AshR2RML.OBDA.PreflightTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      authorizers: [Ash.Policy.Authorizer]

    ets do
      private?(true)
    end

    actions do
      defaults([:read])
    end

    policies do
      policy action_type(:read) do
        authorize_if(actor_attribute_equals(:role, :admin))
      end
    end

    attributes do
      uuid_primary_key(:id)
    end
  end

  defmodule AttrTenant do
    use Ash.Resource,
      domain: AshR2RML.OBDA.PreflightTest.Domain,
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(true)
    end

    multitenancy do
      strategy(:attribute)
      attribute(:tenant_id)
    end

    actions do
      defaults([:read])
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:tenant_id, :string, allow_nil?: false, public?: true)
    end
  end

  defmodule GlobalTenant do
    use Ash.Resource,
      domain: AshR2RML.OBDA.PreflightTest.Domain,
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(true)
    end

    multitenancy do
      strategy(:attribute)
      attribute(:tenant_id)
      global?(true)
    end

    actions do
      defaults([:read])
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:tenant_id, :string, public?: true)
    end
  end

  defmodule Plain do
    use Ash.Resource,
      domain: AshR2RML.OBDA.PreflightTest.Domain,
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(true)
    end

    actions do
      defaults([:read])
    end

    attributes do
      uuid_primary_key(:id)
    end
  end

  test "unauthorized actor prunes the resource" do
    assert Preflight.check(Guarded, actor: %{role: :guest}) == :pruned
    assert Preflight.check(Guarded, actor: nil) == :pruned
  end

  test "authorized actor passes" do
    assert Preflight.check(Guarded, actor: %{role: :admin}) == :ok
  end

  test "plain resource without policies passes" do
    assert Preflight.check(Plain) == :ok
  end

  test "multitenant resource without tenant is refused" do
    assert {:error, %Refusal{code: :REFUSED_MISSING_TENANT, subject: AttrTenant}} =
             Preflight.check(AttrTenant)
  end

  test "multitenant resource with tenant passes" do
    assert Preflight.check(AttrTenant, tenant: "t1") == :ok
  end

  test "global? multitenant resource passes without tenant" do
    assert Preflight.check(GlobalTenant) == :ok
  end
end
