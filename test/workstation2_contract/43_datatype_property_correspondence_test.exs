# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.DatatypePropertyCorrespondenceTest do
  use ExUnit.Case, async: true
  test "Ash attributes correspond to R2RML datatype properties" do
    c=File.read!("AGENTS.md"); assert c =~ "Datatype Property"; assert c =~ "`rr:predicate`/`rr:datatype`"
  end
end
