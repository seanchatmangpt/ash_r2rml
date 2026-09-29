# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.SemanticEctoStorageTypeTest do
  use ExUnit.Case, async: true

  alias AshR2RML.SemanticIR
  alias AshR2RML.SemanticIR.{Attribute, Identity, Resource}

  defmodule Point26918 do
    use AshGeo.Geometry, storage_type: :"geometry(Point,26918)"
  end

  test "Ecto projection reuses the Ash type storage contract" do
    assert {:ok, source} = AshR2RML.Semantic.Ecto.render(ir(AshGeo.Geometry))
    assert source =~ ~s(add :"geometry", :geometry,)
  end

  test "narrowed custom Ash storage types remain exact instead of being package-special-cased" do
    assert {:ok, source} = AshR2RML.Semantic.Ecto.render(ir(Point26918))
    assert source =~ ~s(add :"geometry", :"geometry(Point,26918)",)
  end

  defp ir(geometry_type) do
    %SemanticIR{
      ontology_hash: "ontology:sha256:geo",
      profile_hash: "profile:sha256:geo",
      shacl_hash: "shacl:sha256:geo",
      resources: [
        %Resource{
          iri: "https://example.com/resource/Place",
          class_iri: "https://example.com/ontology/Place",
          shape_iri: "https://example.com/shapes/PlaceShape",
          module: "Example.Place",
          repo_module: "Example.Repo",
          table: "places",
          subject_template: "https://example.com/place/{id}",
          identities: [%Identity{name: :primary, keys: [:id], primary?: true}],
          attributes: [
            %Attribute{
              name: :id,
              column: "id",
              predicate_iri: "https://example.com/ontology/id",
              datatype_iri: "http://www.w3.org/2001/XMLSchema#string",
              ash_type: :uuid,
              postgres_type: "UUID",
              min_count: 1,
              max_count: 1,
              nullable: false,
              identity?: true
            },
            %Attribute{
              name: :geometry,
              column: "geometry",
              predicate_iri: "http://www.opengis.net/ont/geosparql#asWKT",
              datatype_iri: "http://www.opengis.net/ont/geosparql#wktLiteral",
              ash_type: geometry_type,
              postgres_type: "GEOMETRY",
              min_count: 0,
              max_count: 1,
              nullable: true
            }
          ],
          relationships: [],
          actions: [],
          policies: []
        }
      ]
    }
  end
end
