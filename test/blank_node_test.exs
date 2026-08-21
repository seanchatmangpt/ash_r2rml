# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.BlankNodeTest do
  use ExUnit.Case, async: true

  defmodule BNodeEntity do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :label, :string, allow_nil?: false, public?: true
    end

    r2rml do
      table_name("bnodes")
      class("https://schema.org/Thing")

      subject do
        template("bnode_{id}")
        term_type(:blank_node)
      end

      property(:label, "https://schema.org/name")
    end
  end

  test "supports W3C blank node termType rr:BlankNode rendering" do
    {:ok, mapping} = AshR2RML.mapping_result(BNodeEntity)
    assert mapping.subject_map.strategy == :blank_node
    assert mapping.subject_map.term_type == :blank_node

    {:ok, ttl} = AshR2RML.render_r2rml(BNodeEntity)
    assert ttl =~ "rr:termType rr:BlankNode"
    assert ttl =~ "rr:template \"bnode_{id}\""
  end
end
