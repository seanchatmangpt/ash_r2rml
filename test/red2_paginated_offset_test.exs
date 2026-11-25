# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Red2PaginatedOffsetTest do
  @moduledoc """
  A pushed-down OFFSET must select the exact slice (no dup, no skip) when the read
  action requires pagination (offset and keyset flavours).
  """

  use ExUnit.Case, async: false

  alias AshR2RML.Mapping.{LogicalTable, Resource, SubjectMap}
  alias AshR2RML.OBDA

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.Red2PaginatedOffsetTest.OffsetReq
      resource AshR2RML.Red2PaginatedOffsetTest.KeysetReq
    end
  end

  defmodule OffsetReq do
    use Ash.Resource,
      primary_read_warning?: false,
      domain: AshR2RML.Red2PaginatedOffsetTest.Domain,
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(false)
    end

    actions do
      defaults([:destroy, create: [:name]])

      read :read do
        primary?(true)
        pagination(offset?: true, required?: true, default_limit: 2, max_page_size: 2)
        prepare(build(sort: [name: :asc]))
      end
    end

    identities do
      identity(:by_name, [:name], pre_check_with: AshR2RML.Red2PaginatedOffsetTest.Domain)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:name, :string, allow_nil?: false, public?: true)
    end
  end

  defmodule KeysetReq do
    use Ash.Resource,
      primary_read_warning?: false,
      domain: AshR2RML.Red2PaginatedOffsetTest.Domain,
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(false)
    end

    actions do
      defaults([:destroy, create: [:name]])

      read :read do
        primary?(true)
        pagination(keyset?: true, required?: true, default_limit: 2, max_page_size: 2)
        prepare(build(sort: [name: :asc]))
      end
    end

    identities do
      identity(:by_name, [:name], pre_check_with: AshR2RML.Red2PaginatedOffsetTest.Domain)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:name, :string, allow_nil?: false, public?: true)
    end
  end

  @names ["a", "b", "c", "d", "e"]

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
      metadata: %{source: :red2_paginated_offset_test}
    }

    [{resource, mapping}]
  end

  defp seed(resource) do
    clear(resource)

    for name <- @names do
      resource
      |> Ash.Changeset.for_create(:create, %{name: name}, domain: Domain)
      |> Ash.create!(authorize?: false, domain: Domain)
    end
  end

  defp clear(resource) do
    case Ash.read!(resource, authorize?: false, domain: Domain, page: [limit: 2]).results do
      [] ->
        :ok

      rows ->
        Enum.each(rows, &Ash.destroy!(&1, action: :destroy, authorize?: false, domain: Domain))
        clear(resource)
    end
  end

  defp slice(resource, prefix, modifiers) do
    seed(resource)

    select =
      "SELECT ?s WHERE { ?s a <http://schema.org/Person> } ORDER BY ?s " <> modifiers

    assert {:ok, result} = OBDA.query(spec(resource, prefix), select, domain: Domain)
    Enum.map(result.bindings, &to_string(&1["s"]))
  end

  defp expect(prefix, names), do: Enum.map(names, &"urn:uuid:#{prefix}-#{&1}")

  test "required offset pagination: OFFSET 2 LIMIT 2 returns exactly c,d" do
    assert slice(OffsetReq, "oreq", "LIMIT 2 OFFSET 2") == expect("oreq", ["c", "d"])
  end

  test "required offset pagination: OFFSET 1 without LIMIT returns b..e" do
    assert slice(OffsetReq, "oreq2", "OFFSET 1") == expect("oreq2", ["b", "c", "d", "e"])
  end

  test "required offset pagination: OFFSET 3 LIMIT 5 spans pages without dup" do
    assert slice(OffsetReq, "oreq3", "LIMIT 5 OFFSET 3") == expect("oreq3", ["d", "e"])
  end

  test "required keyset pagination: OFFSET 2 LIMIT 2 returns exactly c,d" do
    assert slice(KeysetReq, "kreq", "LIMIT 2 OFFSET 2") == expect("kreq", ["c", "d"])
  end

  test "required keyset pagination: OFFSET 1 without LIMIT returns b..e" do
    assert slice(KeysetReq, "kreq2", "OFFSET 1") == expect("kreq2", ["b", "c", "d", "e"])
  end
end
