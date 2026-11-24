# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Dialyzer warnings are not baseline debt. Keep this list empty unless a
# documented analyser limitation cannot be represented truthfully in source.
[
  # Analyser limitation (third-party macro expansion): `use Spark.Dsl.Extension`
  # in AshR2RML.Resource expands to generated code attributed to line 1 that
  # branches on a compile-time boolean; Dialyzer reports the dead `false` arm.
  # There is no source line in this repository to change.
  {"lib/ash_r2rml/resource.ex", :pattern_match, 1},
  # Analyser limitation (success typing through SPARQL.ex protocol dispatch):
  # Dialyzer infers AshR2RML.SPARQL.Local.query/3 can only return {:error, _}.
  # Runtime witness (v26.9.25): Local.query(graph, "SELECT ?s WHERE { ?s ?p ?o }")
  # returns {:ok, %Observation{}}; the in-memory OBDA suites
  # (test/obda_in_memory_*_test.exs) exercise this exact {:ok, observation} arm.
  {"lib/ash_r2rml/obda_in_memory.ex", :pattern_match, {168, 16}},
  # Same inference cascades: because Local.query/3 is inferred as error-only, the success-arm
  # helpers (canonical_order/2, read_rows result clauses) are reported unreachable. All of them
  # execute in test/obda_in_memory_*, test/inmemory_canonical_order_test.exs.
  {"lib/ash_r2rml/obda_in_memory.ex", :unused_fun, {176, 8}},
  {"lib/ash_r2rml/obda_in_memory.ex", :pattern_match_cov, 258},
  {"lib/ash_r2rml/obda_in_memory.ex", :pattern_match_cov, 262},
  {"lib/ash_r2rml/obda_in_memory.ex", :pattern_match, {262, 69}},
  # Third-party macro expansion attributed to line 1 (compile-time boolean arm), as for resource.ex.
  {"lib/ash_r2rml/obda_in_memory.ex", :pattern_match, 1},
  {"lib/ash_r2rml/datatype_registry.ex", :pattern_match, 1}
]
