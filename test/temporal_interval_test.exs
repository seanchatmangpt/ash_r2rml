# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.TemporalIntervalTest do
  @moduledoc """
  `temporal start_attribute:, end_attribute:` projects to `time:hasBeginning` / `time:hasEnd`
  as `xsd:dateTime`. Real Ash ETS resources and the real in-memory OBDA engine; each fixture is
  compiled inside its own test so a DSL failure is local to that test.
  """
  use ExUnit.Case, async: true

  alias AshR2RML.OBDA.Adapter
  alias AshR2RML.OBDA.Adapter.InMemoryConfig
  alias AshR2RML.Temporal

  @begin_iri "http://www.w3.org/2006/time#hasBeginning"
  @end_iri "http://www.w3.org/2006/time#hasEnd"
  @xsd_datetime "http://www.w3.org/2001/XMLSchema#dateTime"

  defp fixture(attrs, temporal_entries) do
    name = Module.concat(__MODULE__, "Ev#{System.unique_integer([:positive])}")
    domain = Module.concat(name, Domain)
    loc = Macro.Env.location(__ENV__)

    Module.create(
      name,
      quote do
        use Ash.Resource,
          domain: unquote(domain),
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshR2RML.Resource]

        ets do
          private? false
        end

        r2rml do
          table_name("events")
          class "https://schema.org/Event"
          subject template: "urn:uuid:{id}"
          property :label, "https://schema.org/name"
          unquote_splicing(temporal_entries)
        end

        actions do
          defaults [:read]

          create :create do
            primary? true
            accept :*
          end
        end

        attributes do
          uuid_primary_key :id
          attribute :label, :string, public?: true
          unquote_splicing(attrs)
        end
      end,
      loc
    )

    Module.create(
      domain,
      quote do
        use Ash.Domain, validate_config_inclusion?: false

        resources do
          resource unquote(name)
        end
      end,
      loc
    )

    {name, domain}
  end

  defp datetime_attrs do
    [
      quote(do: attribute(:starts_at, :utc_datetime, public?: true)),
      quote(do: attribute(:ends_at, :utc_datetime, public?: true))
    ]
  end

  defp pair_fixture do
    fixture(datetime_attrs(), [quote(do: temporal(start_attribute: :starts_at, end_attribute: :ends_at))])
  end

  defp create!({resource, domain}, attrs) do
    resource
    |> Ash.Changeset.for_create(:create, attrs, domain: domain)
    |> Ash.create!(domain: domain)
  end

  defp query({resource, domain}, sparql) do
    {:ok, mapping} = AshR2RML.Resource.Info.mapping_result(resource)
    config = %InMemoryConfig{specs: [{resource, mapping}], read_opts: [domain: domain]}
    Adapter.dispatch(config, sparql)
  end

  defp pom(mapping, predicate) do
    Enum.find(mapping.predicate_object_maps, &(&1.predicate_iri == predicate))
  end

  test "predicate constants match OWL-Time" do
    assert Temporal.has_beginning() == @begin_iri
    assert Temporal.has_end() == @end_iri
  end

  test "mapping carries both bounds as xsd:dateTime column literals" do
    {resource, _} = pair_fixture()
    assert {:ok, mapping} = AshR2RML.Resource.Info.mapping_result(resource)

    for {predicate, attribute} <- [{@begin_iri, :starts_at}, {@end_iri, :ends_at}] do
      assert %{attribute: ^attribute, object_map: om} = pom(mapping, predicate)
      assert om.term_type == :literal
      assert om.datatype.rdf_datatype == @xsd_datetime
    end
  end

  test "start-only temporal emits only hasBeginning" do
    {resource, _} =
      fixture(datetime_attrs(), [quote(do: temporal(start_attribute: :starts_at))])

    assert {:ok, mapping} = AshR2RML.Resource.Info.mapping_result(resource)
    assert pom(mapping, @begin_iri)
    assert pom(mapping, @end_iri) == nil
  end

  test "closed interval projects xsd:dateTime lexical forms through OBDA" do
    fix = pair_fixture()
    ev = create!(fix, %{starts_at: ~U[2026-01-02 03:04:05Z], ends_at: ~U[2026-02-03 04:05:06Z]})

    assert {:ok, obs} =
             query(fix, "SELECT ?s ?b ?e WHERE { ?s <#{@begin_iri}> ?b . ?s <#{@end_iri}> ?e }")

    assert [row] = obs.bindings
    assert row["s"] == "urn:uuid:#{ev.id}"
    assert row["b"] == ~U[2026-01-02 03:04:05Z]
    assert row["e"] == ~U[2026-02-03 04:05:06Z]
  end

  test "nil end is an open interval: no hasEnd triple, hasBeginning intact" do
    fix = pair_fixture()
    create!(fix, %{starts_at: ~U[2026-05-06 07:08:09Z], ends_at: nil})

    assert {:ok, ends} = query(fix, "SELECT ?e WHERE { ?s <#{@end_iri}> ?e }")
    assert ends.bindings == []

    assert {:ok, begins} = query(fix, "SELECT ?b WHERE { ?s <#{@begin_iri}> ?b }")
    assert [%{"b" => b}] = begins.bindings
    assert b == ~U[2026-05-06 07:08:09Z]
  end

  test "nil start emits no hasBeginning triple" do
    fix = pair_fixture()
    create!(fix, %{starts_at: nil, ends_at: ~U[2026-05-06 07:08:09Z]})

    assert {:ok, obs} = query(fix, "SELECT ?b WHERE { ?s <#{@begin_iri}> ?b }")
    assert obs.bindings == []
  end

  defp assert_refused(attrs, entries, message) do
    assert_raise RuntimeError, message, fn -> fixture(attrs, entries) end
  end

  test "temporal with neither attribute is refused" do
    assert_refused(datetime_attrs(), [quote(do: temporal([]))], ~r/at least one of start_attribute/)
  end

  test "unknown start attribute is refused" do
    assert_refused(
      datetime_attrs(),
      [quote(do: temporal(start_attribute: :nope))],
      ~r/unknown Ash attribute/
    )
  end

  test "date-only bound is refused" do
    attrs = [quote(do: attribute(:starts_at, :date, public?: true))]

    assert_refused(attrs, [quote(do: temporal(start_attribute: :starts_at))], ~r/date-time attributes/)
  end

  test "string bound is refused" do
    attrs = [quote(do: attribute(:ends_at, :string, public?: true))]

    assert_refused(attrs, [quote(do: temporal(end_attribute: :ends_at))], ~r/date-time attributes/)
  end

  test "Range attribute as a temporal bound is refused" do
    attrs = [
      quote(do: attribute(:window, Ash.Type.Range, constraints: [inner_type: :datetime], public?: true))
    ]

    assert_refused(attrs, [quote(do: temporal(start_attribute: :window))], ~r/Ash.Type.Range packs both bounds/)
  end

  test "Range attribute as a plain property is refused and points to temporal" do
    attrs = [
      quote(do: attribute(:window, Ash.Type.Range, constraints: [inner_type: :datetime], public?: true))
    ]

    assert_refused(
      attrs,
      [quote(do: property(:window, "https://schema.org/temporalCoverage"))],
      ~r/map them with `temporal`/
    )
  end

  test "range_type?/1 and datetime_type?/1 classify Ash types" do
    assert Temporal.range_type?(Ash.Type.Range)
    refute Temporal.range_type?(Ash.Type.String)
    assert Temporal.datetime_type?(Ash.Type.UtcDatetime)
    assert Temporal.datetime_type?(:naive_datetime)
    refute Temporal.datetime_type?(Ash.Type.Date)
  end
end
