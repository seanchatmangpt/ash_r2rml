# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

AshR2RML.DataLayerContract.exclude_postgres_by_default!()

defmodule AshR2RML.DataLayerContractTest do
  @moduledoc """
  The data-layer contract on `Ash.DataLayer.Ets` (always): byte-identical R2RML across input
  order, subject IRI round trip (including `acme/west #1`), actor/tenant isolation and
  sensitive-attribute refusal, over real Ash resources and `AshR2RML.OBDA.InMemory`.
  """
  use ExUnit.Case, async: true

  use AshR2RML.DataLayerContract.Cases, layer: AshR2RML.DataLayerContract.Ets
end

if Code.ensure_loaded?(AshSqlite.DataLayer) do
  defmodule AshR2RML.DataLayerContractSqliteTest do
    @moduledoc "The same contract on a real file-backed AshSqlite database."
    use ExUnit.Case, async: false

    @moduletag :sqlite

    setup_all do
      AshR2RML.DataLayerContract.Db.start_sqlite!()
      :ok
    end

    use AshR2RML.DataLayerContract.Cases, layer: AshR2RML.DataLayerContract.Sqlite
  end
end

if Code.ensure_loaded?(AshPostgres.DataLayer) do
  defmodule AshR2RML.DataLayerContractPostgresTest do
    @moduledoc "The same contract on real Postgres (`ASH_R2RML_POSTGRES_URL`); excluded by default."
    use ExUnit.Case, async: false

    @moduletag :postgres

    setup_all do
      AshR2RML.DataLayerContract.Db.start_postgres!()
      :ok
    end

    use AshR2RML.DataLayerContract.Cases, layer: AshR2RML.DataLayerContract.Postgres
  end
end
