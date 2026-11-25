# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RedPaginatedTest do
  @moduledoc """
  OBDA.InMemory materializes resources whose read action is paginated.
  """

  use ExUnit.Case, async: false

  alias AshR2RML.Mapping.{LogicalTable, Resource, SubjectMap}
  alias AshR2RML.OBDA

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.RedPaginatedTest.OffsetPerson
      resource AshR2RML.RedPaginatedTest.KeysetPerson
      resource AshR2RML.RedPaginatedTest.RequiredPerson
    end
  end

  defmodule OffsetPerson do
    use Ash.Resource, domain: AshR2RML.RedPaginatedTest.Domain, data_layer: Ash.DataLayer.Ets

    ets do
      private?(false)
    end

    actions do
      defaults(create: [:name])

      read :read do
        primary?(true)
        pagination(offset?: true, default_limit: 2)
      end
    end

    identities do
      identity(:by_name, [:name], pre_check_with: AshR2RML.RedPaginatedTest.Domain)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:name, :string, allow_nil?: false, public?: true)
    end
  end

  defmodule KeysetPerson do
    use Ash.Resource, domain: AshR2RML.RedPaginatedTest.Domain, data_layer: Ash.DataLayer.Ets

    ets do
      private?(false)
    end

    actions do
      defaults(create: [:name])

      read :read do
        primary?(true)
        pagination(keyset?: true, default_limit: 2)
      end
    end

    identities do
      identity(:by_name, [:name], pre_check_with: AshR2RML.RedPaginatedTest.Domain)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:name, :string, allow_nil?: false, public?: true)
    end
  end

  defmodule RequiredPerson do
    use Ash.Resource, domain: AshR2RML.RedPaginatedTest.Domain, data_layer: Ash.DataLayer.Ets

    ets do
      private?(false)
    end

    actions do
      defaults(create: [:name])

      read :read do
        primary?(true)
        pagination(offset?: true, required?: true, default_limit: 100)
      end
    end

    identities do
      identity(:by_name, [:name], pre_check_with: AshR2RML.RedPaginatedTest.Domain)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:name, :string, allow_nil?: false, public?: true)
    end
  end

  @select "SELECT ?s WHERE { ?s a <http://schema.org/Person> }"
  @names ["a", "b", "c"]

  defp spec(resource, prefix) do
    mapping = %Resource{
      ash_resource: resource,
      logical_table: %LogicalTable{table_name: prefix},
      subject_map: %SubjectMap{
        strategy: :template,
        value: "urn:uuid:#{prefix}-{name}",
        term_type: :iri
      },
      class_iris: ["http://schema.org/Person"],
      identities: [[:name]],
      metadata: %{source: :red_paginated_test}
    }

    [{resource, mapping}]
  end

  defp seed(resource) do
    # `page: false` is refused by a required-pagination action, so page explicitly.
    resource
    |> Ash.read!(authorize?: false, domain: Domain, page: [limit: 100])
    |> Map.fetch!(:results)
    |> Enum.each(&Ash.destroy!(&1, authorize?: false, domain: Domain))

    for name <- @names do
      resource
      |> Ash.Changeset.for_create(:create, %{name: name}, domain: Domain)
      |> Ash.create!(authorize?: false, domain: Domain)
    end
  end

  defp subjects(resource, prefix) do
    seed(resource)
    assert {:ok, result} = OBDA.query(spec(resource, prefix), @select, domain: Domain)
    result.bindings |> Enum.map(&to_string(&1["s"])) |> Enum.sort()
  end

  test "H14 offset-paginated read action materializes all rows" do
    assert subjects(OffsetPerson, "off") == Enum.map(@names, &"urn:uuid:off-#{&1}")
  end

  test "H14 keyset-paginated read action materializes all rows" do
    assert subjects(KeysetPerson, "key") == Enum.map(@names, &"urn:uuid:key-#{&1}")
  end

  test "H14 required-pagination read action materializes all rows" do
    assert subjects(RequiredPerson, "req") == Enum.map(@names, &"urn:uuid:req-#{&1}")
  end
end
