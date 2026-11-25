# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OBDA.AdapterTest.Domain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshR2RML.OBDA.AdapterTest.Organization
    resource AshR2RML.OBDA.AdapterTest.Person
  end
end

defmodule AshR2RML.OBDA.AdapterTest.Organization do
  @moduledoc false
  use Ash.Resource,
    domain: AshR2RML.OBDA.AdapterTest.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML.Resource]

  # Served through OBDA.query, so the table must be readable from the query worker process:
  # private?(false). Only adapter_test.exs touches these resources.
  ets do
    private?(false)
  end

  r2rml do
    table_name("adapter_organizations")
    class("https://schema.org/Organization")
    subject(template: "urn:uuid:{id}")
    property(:name, "https://schema.org/name")
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
  end
end

defmodule AshR2RML.OBDA.AdapterTest.Person do
  @moduledoc false
  use Ash.Resource,
    domain: AshR2RML.OBDA.AdapterTest.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML.Resource]

  ets do
    private?(false)
  end

  r2rml do
    table_name("adapter_people")
    class("https://schema.org/Person")
    subject(template: "urn:uuid:{id}")
    property(:name, "https://schema.org/name")
    reference(:organization, "https://schema.org/memberOf")
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name, :organization_id]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :organization_id, :uuid, allow_nil?: true, public?: true
  end

  relationships do
    belongs_to :organization, AshR2RML.OBDA.AdapterTest.Organization do
      source_attribute :organization_id
      destination_attribute :id
      attribute_writable? true
    end
  end
end

defmodule AshR2RML.OBDA.AdapterTest do
  @moduledoc """
  Chicago-style: dispatches through `AshR2RML.OBDA.Adapter.dispatch/3` to the real
  `AshR2RML.OBDA.InMemory` engine against a real, non-private `Ash.DataLayer.Ets` resource -- no
  mocked collaborator.
  """
  use ExUnit.Case, async: false

  alias AshR2RML.OBDA.Adapter
  alias AshR2RML.OBDA.Adapter.InMemoryConfig
  alias AshR2RML.OBDA.AdapterTest.{Domain, Organization, Person}

  setup do
    for resource <- [Person, Organization] do
      resource
      |> Ash.read!(domain: Domain)
      |> Enum.each(&Ash.destroy!(&1, domain: Domain))
    end

    :ok
  end

  test "dispatch/3 routes to the real in-memory engine via engine_name/0" do
    assert InMemoryConfig.engine_name() == :in_memory
  end

  test "dispatch/3 queries a real Ash.DataLayer.Ets resource through InMemoryConfig" do
    {:ok, mapping} = AshR2RML.Resource.Info.mapping_result(Organization)

    org =
      Organization
      |> Ash.Changeset.for_create(:create, %{name: "Adapter Co"}, domain: Domain)
      |> Ash.create!(domain: Domain)

    config = %InMemoryConfig{specs: [{Organization, mapping}], read_opts: [domain: Domain]}

    assert {:ok, observation} =
             Adapter.dispatch(config, "SELECT ?s WHERE { ?s a <https://schema.org/Organization> }")

    assert %{"s" => "urn:uuid:#{org.id}"} in observation.bindings
  end

  test "dispatch/3 with multiple specs routes through query_many and joins across resources" do
    {:ok, org_mapping} = AshR2RML.Resource.Info.mapping_result(Organization)
    {:ok, person_mapping} = AshR2RML.Resource.Info.mapping_result(Person)

    org =
      Organization
      |> Ash.Changeset.for_create(:create, %{name: "Multi Co"}, domain: Domain)
      |> Ash.create!(domain: Domain)

    person =
      Person
      |> Ash.Changeset.for_create(:create, %{name: "Ada", organization_id: org.id}, domain: Domain)
      |> Ash.create!(domain: Domain)

    config = %InMemoryConfig{
      specs: [{Organization, org_mapping}, {Person, person_mapping}],
      read_opts: [domain: Domain]
    }

    assert {:ok, observation} =
             Adapter.dispatch(
               config,
               "SELECT ?p ?o WHERE { ?p <https://schema.org/memberOf> ?o }"
             )

    assert observation.bindings == [
             %{
               "p" => "urn:uuid:#{person.id}",
               "o" => "urn:uuid:#{org.id}"
             }
           ]

    assert observation.stats.rows_read == 2
  end
end
