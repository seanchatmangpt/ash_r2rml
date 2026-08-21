# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GraphDslExtTest do
  use ExUnit.Case, async: true

  defmodule TargetResource do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
    end

    r2rml do
      table_name("targets")
      class("https://schema.org/Target")

      subject do
        template("https://example.org/targets/{id}")
      end
    end
  end

  defmodule SourceResource do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :location, AshGeo.Geometry, public?: true
      attribute :embedding, :term, public?: true
    end

    relationships do
      belongs_to :target, TargetResource, allow_nil?: false, public?: true
    end

    r2rml do
      table_name("sources")
      class("https://schema.org/Source")

      subject do
        template("https://example.org/sources/{id}")
      end

      reference(:target, "https://schema.org/targetRef", direction: :incoming, guard_class: "https://schema.org/Target")
    end
  end

  test "compiles relationship edge direction and target guard_class into metadata" do
    {:ok, mapping} = AshR2RML.mapping_result(SourceResource)
    [ref] = mapping.reference_object_maps

    assert ref.metadata.direction == :incoming
    assert ref.metadata.guard_class == "https://schema.org/Target"
  end

  test "evaluates GeoSPARQL and Vector query functions in Ash expression context" do
    import Ash.Expr

    expr1 = expr(AshR2RML.Functions.GeofDistance.geof_distance(location, "POINT(0 0)"))
    expr2 = expr(AshR2RML.Functions.GeofSfIntersects.geof_sf_intersects(location, "POLYGON((0 0, 0 1, 1 1, 1 0, 0 0))"))
    expr3 = expr(AshR2RML.Functions.VecCosineSimilarity.vec_cosine_similarity(embedding, [0.1, 0.2, 0.3]))

    assert match?(%Ash.Query.Call{}, expr1)
    assert match?(%Ash.Query.Call{}, expr2)
    assert match?(%Ash.Query.Call{}, expr3)
  end
end
