# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.DataLayer.EtsBackendTest do
  use ExUnit.Case, async: true

  alias AshR2RML.GrandExample.{Organization, Person}
  alias AshR2RML.Introspection
  alias AshR2RML.Refusal

  describe "backend/1" do
    test "identifies Ash.DataLayer.Ets-backed resources as :ets" do
      assert Introspection.backend(Organization) == :ets
      assert Introspection.backend(Person) == :ets
    end

    test "returns :unknown for a plain module that is not an Ash resource" do
      assert Introspection.backend(String) == :unknown
    end
  end

  describe "table_name/1 on an ETS-backed resource" do
    test "refuses when the resource declares no explicit ets table" do
      assert {:error, %Refusal{code: :REFUSED_INVALID_LOGICAL_TABLE}} = Introspection.table_name(Organization)
      assert {:error, %Refusal{code: :REFUSED_INVALID_LOGICAL_TABLE}} = Introspection.table_name(Person)
    end
  end

  describe "schema_name/1 on an ETS-backed resource" do
    test "is nil -- ETS has no relational schema concept" do
      assert Introspection.schema_name(Organization) == nil
    end
  end
end
