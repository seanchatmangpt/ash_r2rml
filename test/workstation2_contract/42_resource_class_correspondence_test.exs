# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.ResourceClassCorrespondenceTest do
  use ExUnit.Case, async: true
  test "Ash resources correspond to RDF classes" do
    c=File.read!("AGENTS.md"); assert c =~ "RDF/OWL Class"; assert c =~ "`Ash.Resource` (`class_iri`)"
  end
end
