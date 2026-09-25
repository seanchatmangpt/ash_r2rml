# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Semantic.EctoDeclaredStorageTest do
  use ExUnit.Case, async: true

  alias AshR2RML.SemanticIR
  alias SemanticIR.{Attribute, Identity, Resource}

  defp ir(geometry_ash_type, geometry_postgres_type) do
    %SemanticIR{
      ontology_hash: "h",
      profile_hash: "h",
      shacl_hash: "h",
      resources: [
        %Resource{
          iri: "https://example.com/ontology/Place",
          class_iri: "https://example.com/ontology/Place",
          shape_iri: "https://example.com/shapes/PlaceShape",
          module: "Compliance.Place",
          table: "compliance_places",
          subject_template: "https://example.com/id/place/{id}",
          identities: [%Identity{name: :primary, primary?: true, keys: [:id]}],
          attributes: [
            %Attribute{
              name: :id,
              column: "id",
              predicate_iri: "https://example.com/ontology/id",
              datatype_iri: "http://www.w3.org/2001/XMLSchema#string",
              ash_type: :string,
              postgres_type: "TEXT",
              min_count: 1,
              max_count: 1,
              nullable: false
            },
            %Attribute{
              name: :geometry,
              column: "geometry",
              predicate_iri: "http://www.opengis.net/ont/geosparql#asWKT",
              datatype_iri: "http://www.opengis.net/ont/geosparql#wktLiteral",
              ash_type: geometry_ash_type,
              postgres_type: geometry_postgres_type,
              min_count: 1,
              max_count: 1,
              nullable: false
            }
          ],
          relationships: []
        }
      ]
    }
  end

  test "explicitly declared TEXT storage projects a non-builtin Ash type to an Ecto :text column" do
    assert {:ok, source} = AshR2RML.Semantic.Ecto.render(ir(AshGeo.Geometry, "TEXT"))
    assert source =~ ~s(add :"geometry", :text, null: false, primary_key: false)
    assert source =~ ~s(add :"id", :text, null: false, primary_key: true)
  end

  test "undeclared or unknown storage for a non-builtin Ash type still fails closed" do
    for postgres_type <- [nil, "GEOMETRY(POINT, 4326)"] do
      assert {:error, refusal} = AshR2RML.Semantic.Ecto.render(ir(AshGeo.Geometry, postgres_type))
      assert refusal.code == :REFUSED_DATATYPE_CAST_NOT_LOSSLESS
      assert refusal.subject == {"Compliance.Place", :geometry}
    end
  end
end
