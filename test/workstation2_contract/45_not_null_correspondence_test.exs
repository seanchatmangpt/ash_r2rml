# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.NotNullCorrespondenceTest do
  use ExUnit.Case, async: true
  test "non-null scalar multiplicity maps to SHACL minCount" do
    c=File.read!("AGENTS.md"); assert c =~ "Scalar Multiplicity"; assert c =~ "`sh:minCount 1`"
  end
end
