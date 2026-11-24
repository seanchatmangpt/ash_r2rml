# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.DatatypeRegistryCoverageTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Datatype.Registry
  alias AshR2RML.Refusal

  @xsd "http://www.w3.org/2001/XMLSchema#"

  defmodule IriType do
    use Ash.Type
    use AshR2RML.Type, semantic_kind: :iri

    @impl Ash.Type
    def storage_type(_), do: :string

    @impl Ash.Type
    def cast_input(value, _), do: {:ok, value}

    @impl Ash.Type
    def cast_stored(value, _), do: {:ok, value}

    @impl Ash.Type
    def dump_to_native(value, _), do: {:ok, value}
  end

  describe "built-in resolutions" do
    test "scalar atoms resolve to exact XSD IRIs and storage types" do
      cases = [
        {:ci_string, "string", :citext},
        {:naive_datetime_usec, "dateTime", :naive_datetime_usec},
        {:time, "time", :time},
        {:date, "date", :date},
        {:float, "double", :float},
        {:atom, "string", :text},
        {:vector, "string", :vector},
        {:array, "string", :array}
      ]

      for {type, local, storage} <- cases do
        assert {:ok, dt} = Registry.resolve(type)
        assert dt.rdf_datatype == @xsd <> local
        assert dt.storage_type == storage
        assert Registry.supported?(type)
      end
    end

    test "Ash type module names normalize to the same contracts" do
      assert {:ok, %{rdf_datatype: @xsd <> "string", storage_type: :citext}} = Registry.resolve(Ash.Type.CiString)

      assert {:ok, %{rdf_datatype: @xsd <> "dateTime", storage_type: :naive_datetime_usec}} =
               Registry.resolve(Ash.Type.NaiveDatetimeUsec)

      assert {:ok, %{rdf_datatype: @xsd <> "time"}} = Registry.resolve(Ash.Type.Time)
      assert {:ok, %{rdf_datatype: @xsd <> "date"}} = Registry.resolve(Ash.Type.Date)
      assert {:ok, %{rdf_datatype: @xsd <> "double"}} = Registry.resolve(Ash.Type.Float)
      assert {:ok, %{rdf_datatype: @xsd <> "string"}} = Registry.resolve(Ash.Type.Atom)
      assert {:ok, %{rdf_datatype: @xsd <> "string", storage_type: :vector}} = Registry.resolve(Ash.Type.Vector)
    end

    test "geo_wkt resolves to the GeoSPARQL wktLiteral, by atom and by AshGeo module name" do
      wkt = "http://www.opengis.net/ont/geosparql#wktLiteral"

      for type <- [:geo_wkt, AshGeo.Geometry, AshGeo.Point] do
        assert {:ok, dt} = Registry.resolve(type)
        assert dt.rdf_datatype == wkt
        assert dt.storage_type == :geometry
      end
    end

    test "storage override wins over the built-in storage type" do
      assert {:ok, %{rdf_datatype: @xsd <> "date", storage_type: :custom}} = Registry.resolve(:date, nil, :custom)
    end

    test "array element tuples are not resolvable and refuse with UNSUPPORTED_ASH_TYPE" do
      assert {:error, %Refusal{code: :UNSUPPORTED_ASH_TYPE}} = Registry.resolve({:array, :integer})
      assert Registry.supported?({:array, :integer}) == false
    end
  end

  describe "refusals" do
    test "AshR2RML.Type with non-literal semantic_kind refuses REFUSED_NON_LITERAL_DATATYPE" do
      assert {:error, %Refusal{code: :REFUSED_NON_LITERAL_DATATYPE}} = Registry.resolve(IriType)
      assert Registry.supported?(IriType) == false
    end

    test "Ash.Type.Range refuses UNSUPPORTED_ASH_TYPE" do
      assert {:error, %Refusal{code: :UNSUPPORTED_ASH_TYPE}} = Registry.resolve(Ash.Type.Range)
      assert Registry.supported?(Ash.Type.Range) == false
    end
  end
end
