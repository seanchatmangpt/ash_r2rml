# SPDX-License-Identifier: MIT
defmodule AshR2RML.KnowledgeHook.ControlOntologyTest do
  use ExUnit.Case, async: true
  alias AshR2RML.KnowledgeHook.ControlOntology

  test "participating TTL parses and carries runtime authority fences" do
    assert {:ok, :admitted} = ControlOntology.validate()
  end

  test "semantic drift fails closed" do
    path = Path.join(System.tmp_dir!(), "ash_r2rml_control_bad_#{System.unique_integer([:positive])}.ttl")
    File.write!(path, "@prefix kh: <https://ash-r2rml.dev/knowledge-hook#> .")
    assert {:error, {:ontology_contract_missing, missing}} = ControlOntology.validate(path)
    assert missing != []
  after
    if is_binary(path), do: File.rm(path)
  end
end
