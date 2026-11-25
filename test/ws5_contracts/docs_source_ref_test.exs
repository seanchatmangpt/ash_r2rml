defmodule AshR2RML.WS5.DocsSourceRefTest do
  use ExUnit.Case, async: true

  test "documentation source ref remains version-bound" do
    config = Mix.Project.config()
    docs = config[:docs].()
    assert docs[:source_ref] == "v" <> config[:version]
  end
end
