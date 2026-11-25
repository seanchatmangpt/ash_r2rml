# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Red2RenderTaskIoTest.Bare do
  use Ash.Resource, domain: nil, data_layer: Ash.DataLayer.Ets

  attributes do
    uuid_primary_key :id
  end
end

defmodule AshR2RML.Red2RenderTaskIoTest do
  @moduledoc """
  `mix ash_r2rml.render` payload goes to stdout as pure Turtle, `-o` writes a file,
  `--no-compile` is accepted, and refusals name subject and evidence.
  """
  use ExUnit.Case, async: false

  @module "AshR2RML.GrandExample.Organization"

  defp mix_render(args) do
    # Warm build so the measured run has nothing to compile.
    System.cmd("mix", ["compile"], env: [{"MIX_ENV", "test"}], stderr_to_stdout: true)

    System.cmd("mix", ["ash_r2rml.render" | args], env: [{"MIX_ENV", "test"}])
  end

  test "R01 stdout carries only Turtle, no compiler chatter" do
    {out, status} = mix_render([@module])
    assert status == 0
    assert out =~ "rr:"
    refute out =~ ~r/^(Compiling|Generated|==> )/m
    assert String.starts_with?(String.trim_leading(out), "@")
  end

  test "R02 -o writes the Turtle to a file and keeps stdout empty" do
    path = Path.join(System.tmp_dir!(), "red2_render_#{System.unique_integer([:positive])}.ttl")
    on_exit(fn -> File.rm(path) end)

    {out, status} = mix_render(["-o", path, @module])
    assert status == 0
    assert File.exists?(path)
    assert File.read!(path) =~ "rr:"
    refute out =~ "rr:"
  end

  test "R03 --output long form writes the same file content as stdout" do
    path = Path.join(System.tmp_dir!(), "red2_render_#{System.unique_integer([:positive])}.ttl")
    on_exit(fn -> File.rm(path) end)

    {stdout_turtle, 0} = mix_render([@module])
    {_out, status} = mix_render(["--output", path, @module])
    assert status == 0
    assert String.trim(File.read!(path)) == String.trim(stdout_turtle)
  end

  test "R04 --no-compile is accepted and renders" do
    {out, status} = mix_render(["--no-compile", @module])
    assert status == 0
    assert out =~ "rr:"
  end

  test "R05 refusal message carries subject and evidence" do
    bare = inspect(AshR2RML.Red2RenderTaskIoTest.Bare)

    error =
      try do
        Mix.Tasks.AshR2rml.Render.run([bare])
        nil
      rescue
        e in Mix.Error -> Exception.message(e)
      end

    assert is_binary(error), "expected a refusal to raise Mix.Error"
    assert error =~ "REFUSED_"
    assert error =~ bare
    assert error =~ "evidence"
  end
end
