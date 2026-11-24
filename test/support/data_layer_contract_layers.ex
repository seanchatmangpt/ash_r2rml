# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

require AshR2RML.DataLayerContract

# ETS: always compiled.
AshR2RML.DataLayerContract.define(AshR2RML.DataLayerContract.Ets, :ets)

# SQLite: compiled only when the optional ash_sqlite dependency is present.
if Code.ensure_loaded?(AshSqlite.DataLayer) do
  AshR2RML.DataLayerContract.define(
    AshR2RML.DataLayerContract.Sqlite,
    :sqlite,
    AshR2RML.DataLayerContract.SqliteRepo
  )
end

# Postgres: AshPostgres is a test dependency; the layer is compiled but only exercised by tests
# tagged :postgres (excluded unless ASH_R2RML_POSTGRES_URL is set).
if Code.ensure_loaded?(AshPostgres.DataLayer) do
  AshR2RML.DataLayerContract.define(
    AshR2RML.DataLayerContract.Postgres,
    :postgres,
    AshR2RML.DataLayerContract.PostgresRepo
  )
end
