# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RedRenderTaskTest do
  @moduledoc """
  `mix ash_r2rml.render` resolves compiled-but-unloaded modules in a fresh VM.
  """
  use ExUnit.Case, async: false

  @module "AshR2RML.GrandExample.Organization"

  defp render_in_fresh_vm(name) do
    System.cmd("mix", ["ash_r2rml.render", name],
      cd: File.cwd!(),
      env: [{"MIX_ENV", "test"}],
      stderr_to_stdout: true
    )
  end

  defp assert_rendered({output, status}) do
    refute output =~ "unknown module"
    assert status == 0, output
    assert output =~ "rr:"
  end

  test "H01 render task resolves a compiled but unloaded module in a fresh VM" do
    assert_rendered(render_in_fresh_vm(@module))
  end

  test "H23 render task works when compile is a no-op on an incremental build" do
    # First run guarantees the build is up to date; second run is the no-op compile.
    _ = render_in_fresh_vm(@module)
    assert_rendered(render_in_fresh_vm(@module))
  end

  test "H34 render task does not report unknown module for on-disk beam in fresh VM" do
    {output, _status} = result = render_in_fresh_vm(@module)
    refute output =~ "unknown module: #{@module}"
    assert_rendered(result)
  end
end
