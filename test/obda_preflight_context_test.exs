# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OBDA.PreflightContextTest do
  @moduledoc """
  Preflight must answer a context-dependent policy exactly as the real `Ash.read/2` does:
  the same `:context` reaches both, over a real `Ash.Policy.SimpleCheck`.
  """

  use ExUnit.Case, async: true

  alias AshR2RML.OBDA.Preflight

  defmodule ContextAllows do
    use Ash.Policy.SimpleCheck

    @impl true
    def describe(_opts), do: "context[:allow_read] is true"

    @impl true
    def match?(_actor, %{subject: %{context: context}}, _opts) when is_map(context) do
      Map.get(context, :allow_read) == true
    end

    def match?(_actor, _authorizer, _opts), do: false
  end

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.OBDA.PreflightContextTest.Gated
    end
  end

  defmodule Gated do
    use Ash.Resource,
      domain: AshR2RML.OBDA.PreflightContextTest.Domain,
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
        authorize_if(AshR2RML.OBDA.PreflightContextTest.ContextAllows)
      end
    end

    attributes do
      uuid_primary_key(:id)
    end
  end

  defp read_outcome(opts) do
    case Ash.read(Gated, opts) do
      {:ok, _rows} -> :ok
      {:error, %Ash.Error.Forbidden{}} -> :pruned
    end
  end

  test "context that allows: preflight and read both permit" do
    context = %{allow_read: true}
    assert read_outcome(context: context) == :ok
    assert Preflight.check(Gated, context: context) == :ok
  end

  test "context that denies: preflight prunes and read is forbidden" do
    context = %{allow_read: false}
    assert read_outcome(context: context) == :pruned
    assert Preflight.check(Gated, context: context) == :pruned
  end

  test "no context: preflight prunes and read is forbidden" do
    assert read_outcome([]) == :pruned
    assert Preflight.check(Gated) == :pruned
  end

  test "preflight agrees with read across contexts, including the Domain option" do
    for context <- [%{allow_read: true}, %{allow_read: false}, %{}] do
      assert Preflight.check(Gated, context: context, domain: Domain) ==
               read_outcome(context: context, domain: Domain)
    end
  end
end
