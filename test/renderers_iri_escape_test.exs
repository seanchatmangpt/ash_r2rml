# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RenderersIriEscapeTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Mapping.{Bundle, GraphMap, ObjectMap}
  alias AshR2RML.Refusal

  defmodule Entity do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :label, :string, allow_nil?: false, public?: true
      attribute :slug, :string, public?: true
    end

    r2rml do
      table_name("iri_entities")
      class("http://xmlns.com/foaf/0.1/Person")
      subject template: "urn:uuid:{id}"
      property(:label, "http://www.w3.org/2000/01/rdf-schema#label")
      property(:slug, "http://purl.org/dc/terms/identifier")
    end
  end

  defp mapping do
    {:ok, mapping} = AshR2RML.mapping_result(Entity)
    mapping
  end

  defp refused({:error, [%Refusal{} = r | _]}), do: r
  defp refused({:error, %Refusal{} = r}), do: r
  defp refused(other), do: flunk("expected a refusal, got: " <> inspect(other))

  defp render(mapping), do: AshR2RML.R2RML.render(%Bundle{resources: [mapping]})

  test "baseline mapping renders" do
    assert {:ok, ttl} = render(mapping())
    assert ttl =~ "<http://www.w3.org/2000/01/rdf-schema#label>"
  end

  for bad <- ["a b", "a>b", "a\"b", "a{b", "a}b", "a|b", "a^b", "a`b", "a\\b", "a\nb", "a\x01b"] do
    test "predicate IRI #{inspect(bad)} is refused" do
      m = mapping()
      [first | rest] = m.predicate_object_maps
      m = %{m | predicate_object_maps: [%{first | predicate_iri: "http://purl.org/dc/terms/" <> unquote(bad)} | rest]}

      assert %Refusal{code: code} = refused(render(m))
      assert code in [:REFUSED_INVALID_TERM_MAP, :REFUSED_RELATIONSHIP_WITHOUT_PREDICATE]
    end
  end

  test "class IRI with an injection payload is refused" do
    m = %{mapping() | class_iris: ["http://xmlns.com/foaf/0.1/X> ; rr:foo <http://xmlns.com/foaf/0.1/Y"]}
    assert %Refusal{code: code} = refused(render(m))
    assert code in [:REFUSED_INVALID_TERM_MAP, :REFUSED_INVALID_CLASS_IRI]
  end

  test "graph constant IRI with a space is refused" do
    m = %{mapping() | graph_maps: [%GraphMap{strategy: :constant, value: "http://purl.org/dc/terms/g h"}]}
    assert %Refusal{code: code} = refused(render(m))
    assert code in [:REFUSED_INVALID_TERM_MAP, :REFUSED_INVALID_GRAPH_MAP]
  end

  test "language plus datatype is refused, not silently dropped" do
    m = mapping()
    [first | rest] = m.predicate_object_maps

    object = %ObjectMap{
      strategy: :column,
      value: "label",
      language: "en",
      datatype: %AshR2RML.Mapping.Datatype{rdf_datatype: "http://www.w3.org/2001/XMLSchema#string"}
    }

    m = %{m | predicate_object_maps: [%{first | object_map: object} | rest]}
    assert %Refusal{code: :REFUSED_INVALID_TERM_MAP} = refused(render(m))
  end

  test "literal template object map emits explicit rr:termType rr:Literal" do
    m = mapping()
    [first | rest] = m.predicate_object_maps
    object = %ObjectMap{strategy: :template, value: "label-{label}", term_type: :literal}
    m = %{m | predicate_object_maps: [%{first | object_map: object} | rest]}

    assert {:ok, ttl} = render(m)
    assert ttl =~ ~s(rr:template "label-{label}"; rr:termType rr:Literal)
  end
end
