# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RedMixPackagingTest do
  @moduledoc """
  H19: a package that declares optional :igniter support must ship its
  installer mix task in the Hex tarball file list.
  """
  use ExUnit.Case, async: true

  @installer "lib/mix/tasks/ash_r2rml.install.ex"

  test "H19 installer task file exists on disk" do
    assert File.regular?(@installer)
  end

  test "H19 package_files includes the installer when :igniter is a declared dep" do
    deps = AshR2RML.MixProject.project()[:deps]
    igniter_declared? = Enum.any?(deps, fn dep -> elem(dep, 0) == :igniter end)
    files = AshR2RML.MixProject.package_files()

    if igniter_declared? do
      assert @installer in files
    else
      # No igniter dep: nothing to ship; the finding is moot.
      refute igniter_declared?
    end
  end
end
