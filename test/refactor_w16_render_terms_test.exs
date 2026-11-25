# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW16RenderTermsTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Mapping.Bundle
  alias AshR2RML.Refusal

  defmodule Entity do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    ets do
      private?(false)
    end

    attributes do
      uuid_primary_key :id
      attribute :label, :string, allow_nil?: false, public?: true
    end

    actions do
      defaults [:read]
    end

    r2rml do
      table_name("w16_render_terms")
      class("http://schema.org/Thing")
      subject template: "http://schema.org/thing/{id}"
      property(:label, "http://schema.org/name")
    end
  end

  defp mapping do
    {:ok, m} = AshR2RML.mapping_result(Entity)
    m
  end

  defp render_subject_type(term_type) do
    m = mapping()
    AshR2RML.R2RML.render(%Bundle{resources: [%{m | subject_map: %{m.subject_map | term_type: term_type}}]})
  end

  defp refusal({:error, [%Refusal{} = r | _]}), do: r
  defp refusal({:error, %Refusal{} = r}), do: r
  defp refusal(other), do: flunk("expected a refusal, got: " <> inspect(other))

  test "a literal subject term type is refused" do
    assert %Refusal{code: :UNSUPPORTED_TERM_TYPE} = refusal(render_subject_type(:literal))
  end

  test "iri and blank_node subject term types stay lawful" do
    assert {:ok, _} = render_subject_type(:iri)
    assert {:ok, _} = render_subject_type(:blank_node)
  end
end
