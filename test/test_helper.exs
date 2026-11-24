# SPDX-FileCopyrightText: 2026 ash_r2rml contributors
#
# SPDX-License-Identifier: MIT

# Tiered tests: `:postgres` is excluded by default; run with `mix test --include postgres`.
# `:sqlite` stays included; lane contract files guard on AshSqlite availability.
ExUnit.start(exclude: [:postgres])
