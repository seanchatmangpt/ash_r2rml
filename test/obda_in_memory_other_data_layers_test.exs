# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OBDA.InMemoryOtherDataLayersTest do
  @moduledoc """
  `AshR2RML.OBDA.InMemory.materialize/3` (lib/ash_r2rml/obda_in_memory.ex) has no data-layer
  gate at all -- `rows_for/3` just calls `Ash.read!/2`. Its moduledoc and naming ("ETS-side
  OBDA") implied it only works against `Ash.DataLayer.Ets`; this suite verifies that claim is
  actually narrower than reality, for real, against two other real Ash data layers:
  `AshCsv.DataLayer` (a real CSV file on disk) and `AshCubDB.DataLayer` (a real CubDB
  key-value store on disk). `ash_csv`/`ash_cubdb` are `:test`-only dependencies of AshR2RML
  itself, used solely to verify this -- AshR2RML's own runtime never depends on them.

  `AshR2RML.DataLayer.backend/1` correctly classifies both as `:unknown` (it only recognizes
  `:postgres`/`:ets` by name) -- that's expected and does not block materialization, since
  `InMemory` never consults `backend/1` at all. `table_name/1` for an `:unknown` backend falls
  through to the module-name-derived default, also verified here.
  """
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  defmodule CsvDomain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.OBDA.InMemoryOtherDataLayersTest.CsvOrganization
    end
  end

  defmodule CsvOrganization do
    use Ash.Resource,
      domain: AshR2RML.OBDA.InMemoryOtherDataLayersTest.CsvDomain,
      data_layer: AshCsv.DataLayer,
      extensions: [AshR2RML]

    csv do
      file(Path.join(System.tmp_dir!(), "ash_r2rml_csv_test_organizations.csv"))
      create?(true)
      header?(true)
      columns([:id, :name, :version])
    end

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
        accept [:name, :version]
      end
    end

    attributes do
      uuid_primary_key :id
      attribute :name, :string, allow_nil?: false, public?: true
      attribute :version, :string, allow_nil?: false, public?: true
    end
  end

  defmodule CubDomain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.OBDA.InMemoryOtherDataLayersTest.CubOrganization
    end
  end

  defmodule CubOrganization do
    use Ash.Resource,
      domain: AshR2RML.OBDA.InMemoryOtherDataLayersTest.CubDomain,
      data_layer: AshCubDB.DataLayer,
      extensions: [AshR2RML]

    cubdb do
      directory(Path.join(System.tmp_dir!(), "ash_r2rml_cubdb_test_#{System.unique_integer([:positive])}"))
    end

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
        accept [:name, :version]
      end
    end

    attributes do
      uuid_primary_key :id
      attribute :name, :string, allow_nil?: false, public?: true
      attribute :version, :string, allow_nil?: false, public?: true
    end
  end

  setup do
    csv_path = Path.join(System.tmp_dir!(), "ash_r2rml_csv_test_organizations.csv")
    File.rm(csv_path)
    on_exit(fn -> File.rm(csv_path) end)
    :ok
  end

  describe "AshCsv.DataLayer" do
    test "backend/1 classifies it as :unknown, table_name/1 falls through to the default, and materialization still works" do
      assert AshR2RML.DataLayer.backend(CsvOrganization) == :unknown
      assert AshR2RML.DataLayer.table_name(CsvOrganization) == "csv_organizations"
    end

    test "AshR2RML.OBDA.InMemory materializes and queries real rows from a real CSV file" do
      {:ok, mapping} = AshR2RML.Resource.Info.mapping_result(CsvOrganization)

      org =
        CsvOrganization
        |> Ash.Changeset.for_create(:create, %{name: "Csv Corp", version: "1.0.0"}, domain: CsvDomain)
        |> Ash.create!(domain: CsvDomain)

      assert {:ok, graph} = AshR2RML.OBDA.InMemory.materialize(CsvOrganization, mapping, domain: CsvDomain)

      subject = RDF.iri("https://schema.org/Organization/#{org.id}")
      assert RDF.Graph.include?(graph, {subject, RDF.iri("https://schema.org/name"), RDF.literal("Csv Corp")})

      assert {:ok, observation} =
               AshR2RML.OBDA.InMemory.query(
                 CsvOrganization,
                 mapping,
                 "SELECT ?s ?name WHERE { ?s a <https://schema.org/Organization> ; <https://schema.org/name> ?name . }",
                 domain: CsvDomain
               )

      assert %{"s" => "https://schema.org/Organization/#{org.id}", "name" => "Csv Corp"} in observation.rows
    end
  end

  describe "AshCubDB.DataLayer" do
    test "backend/1 classifies it as :unknown, table_name/1 falls through to the default, and materialization still works" do
      assert AshR2RML.DataLayer.backend(CubOrganization) == :unknown
      assert AshR2RML.DataLayer.table_name(CubOrganization) == "cub_organizations"
    end

    test "AshR2RML.OBDA.InMemory materializes and queries real rows from a real CubDB store" do
      {:ok, mapping} = AshR2RML.Resource.Info.mapping_result(CubOrganization)

      org =
        CubOrganization
        |> Ash.Changeset.for_create(:create, %{name: "Cub Corp", version: "2.0.0"}, domain: CubDomain)
        |> Ash.create!(domain: CubDomain)

      assert {:ok, graph} = AshR2RML.OBDA.InMemory.materialize(CubOrganization, mapping, domain: CubDomain)

      subject = RDF.iri("https://schema.org/Organization/#{org.id}")
      assert RDF.Graph.include?(graph, {subject, RDF.iri("https://schema.org/name"), RDF.literal("Cub Corp")})

      assert {:ok, observation} =
               AshR2RML.OBDA.InMemory.query(
                 CubOrganization,
                 mapping,
                 "SELECT ?s ?name WHERE { ?s a <https://schema.org/Organization> ; <https://schema.org/name> ?name . }",
                 domain: CubDomain
               )

      assert %{"s" => "https://schema.org/Organization/#{org.id}", "name" => "Cub Corp"} in observation.rows
    end
  end
end
