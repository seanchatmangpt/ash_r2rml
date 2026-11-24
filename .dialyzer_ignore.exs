# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Dialyzer infers `AshR2RML.SPARQL.Local.query/3` as error-only, so every success-arm helper downstream
# (OBDA.InMemory canonical ordering/limits, OBDA.query envelope, Action.Query) is reported unreachable.
# They all execute with real rows in test/obda_in_memory_*, test/obda_query_envelope_test.exs,
# test/action_query_test.exs and test/inmemory_canonical_order_test.exs. Ignores are pinned by file and
# warning class (not line) so they survive edits; a new class in these files still fails the gate.
[
  {"lib/ash_r2rml/resource.ex", :pattern_match, 1},
  {"lib/ash_r2rml/datatype_registry.ex", :pattern_match, 1},
  {"lib/ash_r2rml/obda_in_memory.ex", :pattern_match},
  {"lib/ash_r2rml/obda_in_memory.ex", :pattern_match_cov},
  {"lib/ash_r2rml/obda_in_memory.ex", :unused_fun},
  {"lib/ash_r2rml/obda.ex", :pattern_match},
  {"lib/ash_r2rml/obda.ex", :unused_fun},
  {"lib/ash_r2rml/action/query.ex", :pattern_match}
]
