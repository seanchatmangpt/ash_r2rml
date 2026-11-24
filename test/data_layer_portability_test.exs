# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.DataLayerPortability.Fixture do
  @moduledoc false

  # Builds one resource + domain per data layer from the SAME r2rml mapping block and the same
  # attributes, so the only variable is the data layer.
  defmacro define(name, data_layer, do: layer_dsl) do
    name = Macro.expand(name, __CALLER__)
    domain = Module.concat(name, Domain)
    resource = Module.concat(name, Resource)

    quote do
      defmodule unquote(domain) do
        use Ash.Domain, validate_config_inclusion?: false

        resources do
          resource unquote(resource)
        end
      end

      defmodule unquote(resource) do
        use Ash.Resource,
          domain: unquote(domain),
          data_layer: unquote(data_layer),
          extensions: [AshR2RML]

        unquote(layer_dsl)

        r2rml do
          class_iri("https://schema.org/Organization")
          subject_template("https://schema.org/Organization/{id}")
          table_name("schema_organizations")

          attribute_mappings([
            {:name, "https://schema.org/name"},
            {:version, "https://schema.org/version"}
          ])
        end

        actions do
          defaults [:read, :destroy]

          create :create do
            primary? true
            accept [:id, :name, :version]
          end
        end

        attributes do
          uuid_primary_key :id, writable?: true
          attribute :name, :string, allow_nil?: false, public?: true
          attribute :version, :string, allow_nil?: false, public?: true
        end
      end
    end
  end
end

defmodule AshR2RML.DataLayerPortabilityTest do
  @moduledoc """
  The same mapping IR, the same rows (identical ids) and the same SPARQL query run against every
  real data layer in the test deps: `Ash.DataLayer.Ets`, `AshCsv.DataLayer`, `AshCubDB.DataLayer`.
  Results must be identical across layers. A missing layer module fails the test (no skips).

  `Ash.DataLayer.Simple` is not exercised: it holds no storage of its own (rows are supplied via
  query context), so there is no real persisted store to write the shared rows into.
  """
  use ExUnit.Case, async: false

  require AshR2RML.DataLayerPortability.Fixture, as: Fixture

  @csv_file Path.join(System.tmp_dir!(), "ash_r2rml_portability.csv")
  @cub_dir Path.join(System.tmp_dir!(), "ash_r2rml_portability_cub")

  Fixture.define AshR2RML.DataLayerPortabilityTest.Ets, Ash.DataLayer.Ets do
  end

  Fixture.define AshR2RML.DataLayerPortabilityTest.Csv, AshCsv.DataLayer do
    csv do
      file(Path.join(System.tmp_dir!(), "ash_r2rml_portability.csv"))
      create?(true)
      header?(true)
      columns([:id, :name, :version])
    end
  end

  Fixture.define AshR2RML.DataLayerPortabilityTest.Cub, AshCubDB.DataLayer do
    cubdb do
      directory(Path.join(System.tmp_dir!(), "ash_r2rml_portability_cub"))
    end
  end

  @layers [
    {Ash.DataLayer.Ets, AshR2RML.DataLayerPortabilityTest.Ets.Resource},
    {AshCsv.DataLayer, AshR2RML.DataLayerPortabilityTest.Csv.Resource},
    {AshCubDB.DataLayer, AshR2RML.DataLayerPortabilityTest.Cub.Resource}
  ]

  @query "SELECT ?s ?name ?version WHERE { ?s a <https://schema.org/Organization> ; " <>
           "<https://schema.org/name> ?name ; <https://schema.org/version> ?version . }"

  @seed [
    {"Alpha Corp", "1.0.0"},
    {"Beta Corp", "2.0.0"},
    {"Gamma Corp", "3.0.0"}
  ]

  setup do
    File.rm(@csv_file)
    File.rm_rf(@cub_dir)

    on_exit(fn ->
      File.rm(@csv_file)
      File.rm_rf(@cub_dir)
    end)

    :ok
  end

  # One shared helper: seed identical rows, run identical query, return sorted bindings.
  defp run_layer(resource, ids) do
    domain = Module.concat(Enum.drop(Module.split(resource), -1) ++ ["Domain"])

    Enum.zip(ids, @seed)
    |> Enum.each(fn {id, {name, version}} ->
      resource
      |> Ash.Changeset.for_create(:create, %{id: id, name: name, version: version}, domain: domain)
      |> Ash.create!(domain: domain)
    end)

    {:ok, mapping} = AshR2RML.Resource.Info.mapping_result(resource)
    {:ok, observation} = AshR2RML.OBDA.InMemory.query(resource, mapping, @query, domain: domain)

    {mapping, Enum.sort_by(observation.rows, & &1["s"])}
  end

  test "identical mapping, rows and SPARQL yield identical subjects and bindings on every layer" do
    for {layer, resource} <- @layers do
      assert Code.ensure_loaded?(layer),
             "data layer #{inspect(layer)} is unavailable in test deps; portability cannot be verified"

      assert Code.ensure_loaded?(resource),
             "fixture resource #{inspect(resource)} for #{inspect(layer)} failed to compile"

      assert Ash.DataLayer.data_layer(resource) == layer
    end

    ids = Enum.map(@seed, fn _ -> Ash.UUID.generate() end)

    results = for {layer, resource} <- @layers, do: {layer, run_layer(resource, ids)}

    expected_subjects =
      ids |> Enum.map(&"https://schema.org/Organization/#{&1}") |> Enum.sort()

    expected_rows =
      ids
      |> Enum.zip(@seed)
      |> Enum.map(fn {id, {name, version}} ->
        %{"s" => "https://schema.org/Organization/#{id}", "name" => name, "version" => version}
      end)
      |> Enum.sort_by(& &1["s"])

    for {layer, {_mapping, rows}} <- results do
      assert Enum.map(rows, & &1["s"]) == expected_subjects, "subjects differ on #{inspect(layer)}"
      assert rows == expected_rows, "bindings differ on #{inspect(layer)}"
    end

    [{_, {_, first_rows}} | rest] = results

    for {layer, {_mapping, rows}} <- rest do
      assert rows == first_rows, "#{inspect(layer)} diverges from first layer"
    end
  end
end
