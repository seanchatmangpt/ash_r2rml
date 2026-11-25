# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW7RendererSpecTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Mapping.{Bundle, Datatype, ObjectMap}
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
      table_name("w7_renderer_spec")
      class("http://schema.org/Thing")
      subject template: "http://schema.org/thing/{id}"
      property(:label, "http://schema.org/name")
    end
  end

  @string "http://www.w3.org/2001/XMLSchema#string"

  defp render_with(object) do
    {:ok, m} = AshR2RML.mapping_result(Entity)
    [first | rest] = m.predicate_object_maps
    m = %{m | predicate_object_maps: [%{first | object_map: object} | rest]}
    AshR2RML.R2RML.render(%Bundle{resources: [m]})
  end

  defp refusal({:error, [%Refusal{} = r | _]}), do: r
  defp refusal({:error, %Refusal{} = r}), do: r
  defp refusal(other), do: flunk("expected a refusal, got: " <> inspect(other))

  for term_type <- [:iri, :blank_node] do
    test "datatype on a #{term_type} object map is refused" do
      object = %ObjectMap{
        strategy: :column,
        value: "label",
        term_type: unquote(term_type),
        datatype: %Datatype{rdf_datatype: @string}
      }

      assert %Refusal{code: :REFUSED_INVALID_TERM_MAP} = refusal(render_with(object))
    end

    test "language on a #{term_type} object map is refused" do
      object = %ObjectMap{strategy: :column, value: "label", term_type: unquote(term_type), language: "en"}
      assert %Refusal{code: :REFUSED_INVALID_TERM_MAP} = refusal(render_with(object))
    end
  end

  test "literal object maps still render datatype and language" do
    typed = %ObjectMap{strategy: :column, value: "label", datatype: %Datatype{rdf_datatype: @string}}
    assert {:ok, ttl} = render_with(typed)
    assert ttl =~ "rr:datatype <#{@string}>"

    tagged = %ObjectMap{strategy: :column, value: "label", language: "en"}
    assert {:ok, ttl} = render_with(tagged)
    assert ttl =~ ~s(rr:language "en")
  end

  test "iri object map without datatype or language still renders" do
    object = %ObjectMap{strategy: :template, value: "http://schema.org/{label}", term_type: :iri}
    assert {:ok, ttl} = render_with(object)
    refute ttl =~ "rr:datatype"
    refute ttl =~ "rr:language"
  end
end
