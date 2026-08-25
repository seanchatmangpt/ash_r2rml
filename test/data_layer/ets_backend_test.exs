# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.DataLayer.EtsBackendTest do
  use ExUnit.Case, async: true

  alias AshR2RML.DataLayer
  alias AshR2RML.GrandExample.{Organization, Person}

  describe "backend/1" do
    test "identifies Ash.DataLayer.Ets-backed resources as :ets" do
      assert DataLayer.backend(Organization) == :ets
      assert DataLayer.backend(Person) == :ets
    end

    test "returns :unknown for a plain module that is not an Ash resource" do
      assert DataLayer.backend(String) == :unknown
    end
  end

  describe "table_name/1 on an ETS-backed resource" do
    test "falls through to the module-derived default table name" do
      # Ash.DataLayer.Ets exposes no equivalent of AshPostgres.DataLayer.table/1, and these
      # test resources declare no `resource.table/0`, so `table_name/1` resolves through the
      # generic module-name-derived fallback -- same as it does for any other unconfigured
      # resource, regardless of backend.
      assert DataLayer.table_name(Organization) == "organizations"
      assert DataLayer.table_name(Person) == "persons"
    end
  end

  describe "schema_name/1 on an ETS-backed resource" do
    test "is nil -- ETS has no relational schema concept" do
      assert DataLayer.schema_name(Organization) == nil
    end
  end
end
