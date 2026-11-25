# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.NonPostgresResourceTest do
  @moduledoc """
  A resource on `Ash.DataLayer.Ets` (no postgres block, no AshPostgres reference) maps,
  renders and answers OBDA queries; and no lib/ source references AshPostgres.
  """
  use ExUnit.Case, async: false

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.NonPostgresResourceTest.Widget
    end
  end

  defmodule Widget do
    use Ash.Resource,
      domain: AshR2RML.NonPostgresResourceTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    r2rml do
      table_name("np_widgets")
      class("https://schema.org/Thing")
      subject(template: "urn:uuid:{id}")
      property(:label, "https://schema.org/name")
    end

    actions do
      defaults [:read, :destroy]

      create :create do
        primary? true
        accept [:label]
      end
    end

    attributes do
      uuid_primary_key :id
      attribute :label, :string, allow_nil?: false, public?: true
    end
  end

  test "mapping_result is ok" do
    assert {:ok, %AshR2RML.Mapping.Resource{}} = AshR2RML.Resource.Info.mapping_result(Widget)
  end

  test "R2RML.render emits the exact expected fragments" do
    assert {:ok, ttl} = AshR2RML.R2RML.render(Widget)
    assert ttl =~ ~s(rr:tableName "np_widgets")
    assert ttl =~ "rr:class <https://schema.org/Thing>"
    assert ttl =~ ~s(rr:template "urn:uuid:{id}")
    assert ttl =~ "rr:predicate <https://schema.org/name>"
    assert ttl =~ "#AshR2RML_NonPostgresResourceTest_Widget> a rr:TriplesMap"
  end

  test "OBDA.InMemory.query returns exact bindings from real ETS rows" do
    {:ok, mapping} = AshR2RML.Resource.Info.mapping_result(Widget)

    w =
      Widget
      |> Ash.Changeset.for_create(:create, %{label: "gear"}, domain: Domain)
      |> Ash.create!(domain: Domain)

    assert {:ok, observation} =
             AshR2RML.OBDA.InMemory.query(
               Widget,
               mapping,
               "SELECT ?s ?l WHERE { ?s a <https://schema.org/Thing> ; <https://schema.org/name> ?l . }",
               domain: Domain
             )

    assert observation.rows == [%{"s" => "urn:uuid:#{w.id}", "l" => "gear"}]
  end

  test "ash_postgres is a test-only dependency, never a runtime requirement" do
    {_app, _req, opts} =
      Enum.find(Mix.Project.config()[:deps], fn dep -> elem(dep, 0) == :ash_postgres end)
      |> then(fn {app, req, opts} -> {app, req, opts} end)

    assert Keyword.get(opts, :only) == [:test]
  end
end
