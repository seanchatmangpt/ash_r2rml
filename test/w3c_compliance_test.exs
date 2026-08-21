# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.W3CComplianceTest do
  use ExUnit.Case, async: true

  defmodule Article do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :title, :string, allow_nil?: false, public?: true
      attribute :lang_code, :string, allow_nil?: false, public?: true
    end

    r2rml do
      table_name "articles"
      class "https://schema.org/Article"

      subject do
        column :id
      end

      property :title, "https://schema.org/headline", language_column: :lang_code
    end
  end

  test "renders W3C direct column subject map rr:column" do
    {:ok, mapping} = AshR2RML.mapping_result(Article)
    assert mapping.subject_map.strategy == :column
    assert mapping.subject_map.value == "id"

    {:ok, ttl} = AshR2RML.render_r2rml(Article)
    assert ttl =~ "rr:subjectMap [ rr:column \"id\"; rr:class <https://schema.org/Article> ]"
  end

  test "renders W3C dynamic language column rr:language" do
    {:ok, ttl} = AshR2RML.render_r2rml(Article)
    assert ttl =~ "rr:language \"lang_code\""
  end
end
