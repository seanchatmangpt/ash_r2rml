# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.SecurityTest do
  use ExUnit.Case, async: true

  alias AshR2RML.GgenRuntime.Security

  test "admits actor policy context" do
    assert {:ok, %{field_policy_mode: :ash_mediated}} =
             Security.admit(%{actor: %{id: "a1"}, policy: "ash-field-policy"})
  end

  test "requires tenant when tenant scope is declared" do
    assert {:error, :REFUSED_RUNTIME_TENANT_CONTEXT_MISSING} =
             Security.admit(%{actor: %{id: "a1"}, policy: "ash-field-policy", tenant_required: true})
  end
end
