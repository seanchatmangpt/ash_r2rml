# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.InfoFetchMappingTest.Plain do
  @moduledoc false
  use Ash.Resource, domain: nil, data_layer: Ash.DataLayer.Ets

  actions do
    defaults [:read]
  end

  attributes do
    uuid_primary_key :id
  end
end

defmodule AshR2RML.InfoFetchMappingTest.Mapped do
  @moduledoc false
  use Ash.Resource, domain: nil, data_layer: Ash.DataLayer.Ets, extensions: [AshR2RML.Resource]

  r2rml do
    table_name("fetch_mapped")
    class("http://example.com/Mapped")

    subject do
      template("http://example.com/m/{id}")
    end
  end

  actions do
    defaults [:read]
  end

  attributes do
    uuid_primary_key :id
  end
end

defmodule AshR2RML.InfoFetchMappingTest do
  use ExUnit.Case, async: true

  alias AshR2RML.InfoFetchMappingTest.{Mapped, Plain}
  alias AshR2RML.Resource.Info

  test "mapped resource yields its mapping" do
    assert {:ok, %AshR2RML.Mapping.Resource{ash_resource: Mapped}} = Info.fetch_mapping(Mapped)
    assert Info.mapped?(Mapped)
  end

  test "plain Ash resource is not mapped and never raises" do
    assert Info.fetch_mapping(Plain) == {:error, :not_mapped}
    refute Info.mapped?(Plain)
  end

  test "non-resource inputs are not mapped" do
    assert Info.fetch_mapping(String) == {:error, :not_mapped}
    assert Info.fetch_mapping(NoSuchModuleHere) == {:error, :not_mapped}
    assert Info.fetch_mapping(nil) == {:error, :not_mapped}
    assert Info.fetch_mapping("x") == {:error, :not_mapped}
    refute Info.mapped?(42)
  end
end
