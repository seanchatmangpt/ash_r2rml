# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.DoctestFacadeTest do
  use ExUnit.Case, async: true

  test "facade exports its documented functions" do
    assert Code.ensure_loaded?(AshR2RML)

    for {name, arity} <- [
          mapping: 1,
          compile: 1,
          mapping_result: 1,
          render: 1,
          render_r2rml: 1,
          validate: 1
        ] do
      assert function_exported?(AshR2RML, name, arity), "missing AshR2RML.#{name}/#{arity}"
    end

    assert Code.ensure_loaded?(AshR2RML.Validation)
    assert function_exported?(AshR2RML.Validation, :cutover_ready?, 1)
  end
end
