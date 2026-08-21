# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
# SPDX-FileCopyrightText: 2026 ash_r2rml contributors
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.TestHelper do
  @doc "Checks whether a Neo4j server is listening locally before starting background bolt pools."
  def neo4j_available?(port \\ 7687) do
    case :gen_tcp.connect(~c"127.0.0.1", port, [], 50) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      {:error, _} ->
        false
    end
  end
end

# Only start Bolty pools when Neo4j is actively enabled or reachable
if System.get_env("NEO4J_ENABLED") == "true" or AshR2RML.TestHelper.neo4j_available?() do
  AshNeo4j.BoltyHelper.start_bolt6()
  AshNeo4j.BoltyHelper.start_bolt_apoc()
end

bolt_pool_size = Application.get_env(:bolty, Bolt)[:pool_size] || 15

# `:slow` — long-running guards
# excluded by default, run in CI via `--include slow`.
ExUnit.start(exclude: [:show_neo4j, :bolt6, :cypher25, :apoc, :slow], max_cases: bolt_pool_size)
