# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.DomainErrorTest do
  use ExUnit.Case, async: true
  alias AshR2RML.GgenRuntime.DomainError

  test "refusals are never made retryable" do
    assert {:ok, %{retryable: false, standing: :refused}} =
             DomainError.normalize(%{code: "POLICY_DENIED", class: :refusal})
  end

  test "untyped errors fail closed" do
    assert {:error, :REFUSED_RUNTIME_DOMAIN_ERROR_UNTYPED} = DomainError.normalize(%{code: "UNKNOWN"})
  end
end
