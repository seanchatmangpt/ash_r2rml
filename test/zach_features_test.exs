# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Types.GeoPointTestType do
  use Ash.Type

  use AshR2RML.Type,
    xsd_datatype: "http://www.opengis.net/ont/geosparql#wktLiteral"

  @impl Ash.Type
  def storage_type(_), do: :geometry

  @impl Ash.Type
  def cast_input(value, _), do: {:ok, value}

  @impl Ash.Type
  def cast_stored(value, _), do: {:ok, value}

  @impl Ash.Type
  def dump_to_native(value, _), do: {:ok, value}

  @impl Ash.Type
  def dump_to_embedded(value, _), do: {:ok, value}

  @impl AshR2RML.Type
  def to_rdf_lexical(%{lat: lat, lng: lng}) do
    "POINT(#{lng} #{lat})"
  end
end

defmodule AshR2RML.ZachFeaturesTest do
  use ExUnit.Case, async: true

  alias AshR2RML.DataLayer
  alias AshR2RML.Datatype.Registry
  alias AshR2RML.Mapping.Resource
  alias AshR2RML.Policy
  alias AshR2RML.Reactor.CompileR2RML
  alias AshR2RML.Types.GeoPointTestType

  describe "Feature 2: AshR2RML.Type Custom Type Extension" do
    test "custom Ash.Type implementing AshR2RML.Type resolves xsd_datatype automatically" do
      assert Registry.supported?(GeoPointTestType)
      assert {:ok, datatype} = Registry.resolve(GeoPointTestType)
      assert datatype.rdf_datatype == "http://www.opengis.net/ont/geosparql#wktLiteral"
      assert GeoPointTestType.to_rdf_lexical(%{lat: 40.71, lng: -74.0}) == "POINT(-74.0 40.71)"
    end
  end

  describe "Feature 3: AshR2RML.Policy Actor Filtering" do
    test "filter_for_actor/3 returns mapped resource envelope" do
      mapping = %Resource{
        ash_resource: MyApp.User,
        logical_table: %AshR2RML.Mapping.LogicalTable{table_name: "users"},
        subject_map: %AshR2RML.Mapping.SubjectMap{strategy: :template, value: "https://example.org/users/{id}"},
        class_iris: ["https://schema.org/Person"],
        predicate_object_maps: [
          %AshR2RML.Mapping.PredicateObjectMap{
            attribute: :name,
            predicate_iri: "http://xmlns.com/foaf/0.1/name",
            object_map: %AshR2RML.Mapping.ObjectMap{strategy: :column, value: "name"}
          }
        ],
        reference_object_maps: []
      }

      filtered = Policy.filter_for_actor(mapping, %{id: "actor_1"}, [])
      assert length(filtered.predicate_object_maps) == 1
    end
  end

  describe "Feature 4: AshR2RML.Reactor Step" do
    test "CompileR2RML step executes compilation for resources" do
      profile = %{
        class: "https://schema.org/Person",
        attributes: [%{name: :id, type: :string, primary_key?: true}]
      }

      assert {:ok, compilation} = CompileR2RML.run(%{resources: profile}, %{}, [])
      assert compilation.status == :PARTIAL_ALIVE
    end
  end

  describe "Feature 5: AshR2RML.DataLayer Introspection" do
    test "table_name/1 infers relational table name" do
      assert DataLayer.table_name(MyApp.User) == "users"
    end

    test "infer_join_columns/2 returns source and destination column pair" do
      rel = %{source_attribute: :organization_id, destination_attribute: :id}
      assert DataLayer.infer_join_columns(MyApp.User, rel) == {"organization_id", "id"}
    end
  end
end
