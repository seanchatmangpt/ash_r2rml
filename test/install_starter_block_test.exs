# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.InstallStarterBlockTest.Domain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false
end

defmodule AshR2RML.InstallStarterBlockTest do
  @moduledoc """
  Chicago-style: the real installer patches a resource with `uuid_primary_key :id`; the
  patched source is written to a real tmp file, compiled as a real Ash resource, and the
  resulting mapping must verify (no REFUSED_MISSING_SUBJECT_MAP).
  """
  use ExUnit.Case, async: true

  import Igniter.Test

  @path "lib/starter/installed_post.ex"

  test "installer output compiles as a resource whose mapping verifies" do
    igniter =
      test_project(
        files: %{
          @path => """
          defmodule AshR2RML.InstallStarterBlockTest.InstalledPost do
            use Ash.Resource,
              domain: nil,
              data_layer: Ash.DataLayer.Ets

            ets do
              table :installed_posts
            end

            actions do
              defaults [:read]
            end

            attributes do
              uuid_primary_key :id
            end
          end
          """
        }
      )
      |> Igniter.compose_task("ash_r2rml.install", [
        "--target",
        "AshR2RML.InstallStarterBlockTest.InstalledPost"
      ])

    content =
      igniter.rewrite
      |> Rewrite.source!(@path)
      |> Rewrite.Source.get(:content)

    assert content =~ "r2rml do"
    assert content =~ "AshR2RML.Resource"

    dir = Path.join(System.tmp_dir!(), "install_starter_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    file = Path.join(dir, "installed_post.ex")
    File.write!(file, content)

    modules = Code.compile_file(file)
    on_exit(fn -> for {mod, _} <- modules, do: :code.purge(mod) end)

    resource = AshR2RML.InstallStarterBlockTest.InstalledPost
    assert Enum.any?(modules, fn {mod, _} -> mod == resource end)

    assert {:ok, _mapping} = AshR2RML.Resource.Info.mapping_result(resource)
  end
end
