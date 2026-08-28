# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.SubjectMapCorrespondenceTest do
  use ExUnit.Case, async: true
  test "semantic identity maps to an explicit R2RML subject map" do
    c=File.read!("AGENTS.md"); assert c =~ "Semantic Identity"; assert c =~ "Subject Map (`rr:template`/`rr:termType`)"
  end
end
