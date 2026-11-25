# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.AshR2rml.RenderTest.Dom do
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource Mix.Tasks.AshR2rml.RenderTest.Org
  end
end

defmodule Mix.Tasks.AshR2rml.RenderTest.Org do
  use Ash.Resource,
    domain: Mix.Tasks.AshR2rml.RenderTest.Dom,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML.Resource]

  ets do
    private? true
  end

  r2rml do
    table_name("render_orgs")
    class("https://schema.org/Organization")
    subject(template: "urn:uuid:{id}")
    property(:name, "https://schema.org/name")
  end

  actions do
    defaults [:read]
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end
end

defmodule Mix.Tasks.AshR2rml.RenderTest.Plain do
  @moduledoc false
end

defmodule Mix.Tasks.AshR2rml.RenderTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  @org "Mix.Tasks.AshR2rml.RenderTest.Org"
  @dom "Mix.Tasks.AshR2rml.RenderTest.Dom"

  setup do
    Mix.shell(Mix.Shell.IO)
    on_exit(fn -> Mix.shell(Mix.Shell.Process) end)
  end

  test "renders Turtle for a resource" do
    out = capture_io(fn -> Mix.Tasks.AshR2rml.Render.run([@org]) end)
    assert out =~ "rr:TriplesMap"
    assert out =~ "https://schema.org/Organization"
  end

  test "renders Turtle for a domain" do
    out = capture_io(fn -> Mix.Tasks.AshR2rml.Render.run([@dom]) end)
    assert out =~ "rr:TriplesMap"
    assert out =~ "https://schema.org/Organization"
  end

  test "raises on an unmapped module" do
    assert_raise Mix.Error, fn ->
      Mix.Tasks.AshR2rml.Render.run(["Mix.Tasks.AshR2rml.RenderTest.Plain"])
    end
  end

  test "raises on no arguments" do
    assert_raise Mix.Error, ~r/usage/, fn -> Mix.Tasks.AshR2rml.Render.run([]) end
  end
end
