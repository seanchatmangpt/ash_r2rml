# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW9RendererBlankTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Mapping.{Bundle, ObjectMap}
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
      table_name("w9_renderer_blank")
      class("http://schema.org/Thing")
      subject template: "http://schema.org/thing/{id}"
      property(:label, "http://schema.org/name")
    end
  end

  defp render_with(object) do
    {:ok, m} = AshR2RML.mapping_result(Entity)
    [first | rest] = m.predicate_object_maps
    m = %{m | predicate_object_maps: [%{first | object_map: object} | rest]}
    AshR2RML.R2RML.render(%Bundle{resources: [m]})
  end

  defp refusal({:error, [%Refusal{} = r | _]}), do: r
  defp refusal({:error, %Refusal{} = r}), do: r
  defp refusal(other), do: flunk("expected a refusal, got: " <> inspect(other))

  test "constant blank node object map is refused, not raised" do
    object = %ObjectMap{strategy: :constant, value: "b0", term_type: :blank_node}
    assert %Refusal{code: :REFUSED_INVALID_TERM_MAP} = refusal(render_with(object))
  end

  test "unknown term type on a constant object map is refused" do
    object = %ObjectMap{strategy: :constant, value: "x", term_type: :bogus}
    assert %Refusal{code: :UNSUPPORTED_TERM_TYPE} = refusal(render_with(object))
  end

  test "unknown term type on a column object map is refused" do
    object = %ObjectMap{strategy: :column, value: "label", term_type: :bogus}
    assert %Refusal{code: :UNSUPPORTED_TERM_TYPE} = refusal(render_with(object))
  end

  test "unknown strategy on an object map is refused" do
    object = %ObjectMap{strategy: :bogus, value: "label"}
    assert %Refusal{code: :REFUSED_INVALID_TERM_MAP} = refusal(render_with(object))
  end

  test "blank node column and template object maps still render" do
    for strategy <- [:column, :template] do
      object = %ObjectMap{strategy: strategy, value: "label", term_type: :blank_node}
      assert {:ok, ttl} = render_with(object)
      assert ttl =~ "rr:termType rr:BlankNode"
    end
  end

  test "constant iri and literal object maps still render" do
    assert {:ok, _} = render_with(%ObjectMap{strategy: :constant, value: "http://schema.org/Thing", term_type: :iri})
    assert {:ok, _} = render_with(%ObjectMap{strategy: :constant, value: "x", term_type: :literal})
  end
end
