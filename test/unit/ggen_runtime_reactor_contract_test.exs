# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.ReactorContractTest do
  use ExUnit.Case, async: true
  alias AshR2RML.GgenRuntime.ReactorContract

  test "admits consequential step with compensation" do
    assert {:ok, %{rollback_order: :reverse}} =
             ReactorContract.admit(%{step: "publish", on_error: :refuse, consequential: true, compensation: "unpublish"})
  end

  test "refuses consequential step without compensation" do
    assert {:error, :REFUSED_RUNTIME_COMPENSATION_MISSING} =
             ReactorContract.admit(%{step: "publish", on_error: :refuse, consequential: true})
  end
end
