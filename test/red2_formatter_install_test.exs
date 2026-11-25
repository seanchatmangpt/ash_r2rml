# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Red2FormatterInstallTest do
  use ExUnit.Case, async: true

  @installer Path.expand("../lib/mix/tasks/ash_r2rml.install.ex", __DIR__)
  @mix_exs Path.expand("../mix.exs", __DIR__)

  defp installer_source, do: File.read!(@installer)

  describe "installer formatter wiring" do
    test "does not register AshR2RML.Formatter as a second .ex/.exs plugin" do
      refute installer_source() =~ ~r/add_formatter_plugin\(\s*AshR2RML\.Formatter/
    end

    test "registers Spark.Formatter as the single plugin and imports the dep" do
      src = installer_source()
      assert src =~ "import_dep(:ash_r2rml)"
      assert src =~ ~r/add_formatter_plugin\(\s*Spark\.Formatter/
    end

    test "manual fallback instructions do not tell users to add AshR2RML.Formatter plugin" do
      refute installer_source() =~ "plugins: [AshR2RML.Formatter]"
    end
  end

  describe "installer starter block" do
    test "does not guess a table_name by appending s" do
      refute installer_source() =~ ~r/<>\s*"s"/

      if function_exported?(Mix.Tasks.AshR2rml.Install, :starter_block, 1) do
        block = Mix.Tasks.AshR2rml.Install.starter_block(Red2Fixture.Person)
        refute block =~ ~s(table_name "persons")
      end
    end
  end

  describe "installer non-resource targets" do
    test "a target without use Ash.Resource is not a silent no-op" do
      src = installer_source()
      refute src =~ ~r/:error\s*->\s*\{:ok,\s*zipper\}/
      assert src =~ "add_issue"
    end
  end

  describe "package pin" do
    test "mix.exs still pins the 26.11 series" do
      assert File.read!(@mix_exs) =~ ~r/@version\s+"26\.11\./
      assert installer_source() =~ ~s({:ash_r2rml, "~> 26.11"})
    end
  end
end
