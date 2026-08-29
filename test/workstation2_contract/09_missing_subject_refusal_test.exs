# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.MissingSubjectRefusalTest do
  use ExUnit.Case, async: true
  test "missing subject map has a typed refusal" do
    assert File.read!("AGENTS.md") =~ "REFUSED_MISSING_SUBJECT_MAP"
  end
end
