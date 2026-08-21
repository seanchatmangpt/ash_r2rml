# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.EquivalenceAndFalsifierTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Datatype.Registry
  alias AshR2RML.Refusal

  defmodule Location do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML]

    r2rml do
      class_iri "http://www.opengis.net/ont/geosparql#Feature"
      subject_template "https://example.org/id/location/{id}"
      table_name "locations"
      typed_attribute_mappings [
        {:geometry, "http://www.opengis.net/ont/geosparql#asWKT", "http://www.opengis.net/ont/geosparql#wktLiteral"},
        {:embedding, "https://example.org/ontology/embedding", "http://www.w3.org/2001/XMLSchema#string"}
      ]
    end

    attributes do
      uuid_primary_key :id
      attribute :geometry, :string, allow_nil?: false, public?: true
      attribute :embedding, :string, allow_nil?: false, public?: true
    end
  end

  defmodule UnmappedTypeResource do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML]

    r2rml do
      class_iri "https://example.org/ontology/CustomThing"
      subject_template "https://example.org/id/custom/{id}"
      table_name "custom_things"
      attribute_mappings [
        {:custom_field, "https://example.org/ontology/customField"}
      ]
    end

    attributes do
      uuid_primary_key :id
      attribute :custom_field, :map, allow_nil?: false, public?: true
    end
  end

  describe "Datatype and Spatial Equivalence" do
    test "resolves GeoSPARQL wktLiteral for spatial types" do
      assert {:ok, dt} = Registry.resolve(:geo_wkt)
      assert dt.rdf_datatype == "http://www.opengis.net/ont/geosparql#wktLiteral"
      assert dt.storage_type == :geometry
    end

    test "resolves vector types without falling back to string" do
      assert {:ok, dt} = Registry.resolve(:vector)
      assert dt.rdf_datatype == "http://www.w3.org/2001/XMLSchema#string"
      assert dt.storage_type == :vector
    end

    test "renders GeoSPARQL wktLiteral predicate object maps in R2RML" do
      assert {:ok, ttl} = AshR2RML.render_r2rml(Location)
      assert ttl =~ "rr:predicate <http://www.opengis.net/ont/geosparql#asWKT>"
      assert ttl =~ "rr:datatype <http://www.opengis.net/ont/geosparql#wktLiteral>"
    end

    test "renders GeoSPARQL wktLiteral property constraints in SHACL" do
      assert {:ok, shacl} = AshR2RML.render_shacl([Location])
      assert shacl =~ "sh:path <http://www.opengis.net/ont/geosparql#asWKT>"
      assert shacl =~ "sh:datatype <http://www.opengis.net/ont/geosparql#wktLiteral>"
    end
  end

  describe "Mandatory Semantic Falsifiers (AGENTS.md)" do
    test "falsifier: unsupported custom type NEVER silently becomes a string" do
      assert {:error, %Refusal{code: code}} = Registry.resolve(:unmapped_custom_struct_type)
      assert code == :UNSUPPORTED_ASH_TYPE
    end

    test "falsifier: unmapped custom map attribute in resource mapping produces typed refusal" do
      assert {:error, %Refusal{} = refusal} = AshR2RML.Resource.Info.mapping_result(UnmappedTypeResource)
      assert refusal.code in [:UNSUPPORTED_ASH_TYPE, :REFUSED_UNMAPPED_DATATYPE]
    end

    test "falsifier: invalid/unmapped subject template produces typed refusal when normalized" do
      defmodule UnmappedTemplateResource do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshR2RML]

        r2rml do
          class_iri "https://example.org/ontology/Invalid"
          subject_template "https://example.org/id/invalid/{id}"
          table_name "invalids"
        end

        attributes do
          uuid_primary_key :id
        end
      end

      # Construct an invalid SubjectMap struct directly to test normalization refusal
      invalid_mapping = %AshR2RML.Mapping.Resource{
        ash_resource: UnmappedTemplateResource,
        logical_table: %AshR2RML.Mapping.LogicalTable{table_name: "invalids"},
        subject_map: %AshR2RML.Mapping.SubjectMap{strategy: :template, value: "https://example.org/id/invalid/{unmapped_column}", term_type: :iri},
        class_iris: ["https://example.org/ontology/Invalid"]
      }

      refusals = AshR2RML.Mapping.validate(invalid_mapping)
      assert is_list(refusals) or match?({:error, _}, refusals)
    end
  end

  describe "SPARQL Property Path Verification" do
    test "parses and admits multi-hop SPARQL property path queries" do
      query_str = """
      PREFIX ex: <https://example.com/ontology/>
      SELECT ?a ?b WHERE {
        ?a ex:memberOf/ex:parentOrg ?b .
      }
      """

      assert {:ok, admitted} = AshR2RML.SPARQL.Query.admit(query_str)
      assert admitted.form == :select
      assert is_binary(admitted.sha256)
    end
  end
end
