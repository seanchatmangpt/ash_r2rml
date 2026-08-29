# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.OntopJdbcBoundaryTest do
  use ExUnit.Case, async: true
  test "Ontop remains a JDBC projection boundary" do
    c=File.read!("AGENTS.md"); assert c =~ "Ontop connects to `AshPostgres.DataLayer` directly over JDBC"
  end
end
