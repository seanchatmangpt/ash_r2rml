# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OBDA.AdapterTest do
  @moduledoc """
  Chicago-style: dispatches through `AshR2RML.OBDA.Adapter.dispatch/3` to the real
  `AshR2RML.OBDA.InMemory` engine against a real `Ash.DataLayer.Ets` resource -- no
  mocked collaborator.
  """
  use ExUnit.Case, async: true

  alias AshR2RML.GrandExample.{Domain, Organization}
  alias AshR2RML.OBDA.Adapter
  alias AshR2RML.OBDA.Adapter.{InMemoryConfig}

  test "dispatch/3 routes to the real in-memory engine via engine_name/0" do
    assert InMemoryConfig.engine_name() == :in_memory
  end

  test "dispatch/3 queries a real Ash.DataLayer.Ets resource through InMemoryConfig" do
    {:ok, mapping} = AshR2RML.Resource.Info.mapping_result(Organization)

    org =
      Organization
      |> Ash.Changeset.for_create(:create, %{name: "Adapter Co", version: "1.0.0"}, domain: Domain)
      |> Ash.create!(domain: Domain)

    config = %InMemoryConfig{specs: [{Organization, mapping}], read_opts: [domain: Domain]}

    assert {:ok, observation} =
             Adapter.dispatch(config, "SELECT ?s WHERE { ?s a <https://schema.org/Organization> }")

    assert %{"s" => "https://schema.org/Organization/#{org.id}"} in observation.rows
  end
end
