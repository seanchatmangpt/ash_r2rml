# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.POWL.Model do
  @moduledoc """
  POWL 2.0 AST (Transitions, Partial Orders, Choice Graphs) and W3C RDF/OWL Serializer.
  """

  defmodule Transition do
    defstruct [:id, :label, silent?: false]
  end

  defmodule PartialOrder do
    defstruct [:id, children: [], order: MapSet.new()]
  end

  defmodule ChoiceGraph do
    defstruct [:id, children: [], edges: MapSet.new()]
  end

  @doc "Renders a POWL 2.0 AST into standards-valid W3C OWL 2 RDF Turtle conforming to https://w3id.org/powl/v2"
  def to_owl_turtle(powl_model, base_iri \\ "https://example.org/process/") do
    triples = serialize_node(powl_model, base_iri)

    header = """
    @prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .
    @prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
    @prefix owl: <http://www.w3.org/2002/07/owl#> .
    @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
    @prefix powl: <https://w3id.org/powl/v2#> .

    """

    header <> Enum.join(triples, "\n")
  end

  defp serialize_node(%Transition{id: id, label: label, silent?: silent?}, base_iri) do
    iri = "<#{base_iri}#{id}>"
    class = if silent?, do: "powl:SilentTransition", else: "powl:Transition"

    lines = [
      "#{iri} a #{class} ;",
      "    rdfs:label \"#{label}\" ;",
      "    powl:activityLabel \"#{label}\"^^xsd:string ."
    ]

    lines
  end

  defp serialize_node(%PartialOrder{id: id, children: children, order: order}, base_iri) do
    iri = "<#{base_iri}#{id}>"
    child_iris = Enum.map(children, &"<#{base_iri}#{&1.id}>")

    child_triples = Enum.flat_map(children, &serialize_node(&1, base_iri))

    order_triples =
      for {i, j} <- order do
        source = Enum.at(child_iris, i)
        target = Enum.at(child_iris, j)
        "#{source} powl:precedes #{target} ."
      end

    has_children =
      Enum.map(child_iris, fn c_iri ->
        "#{iri} powl:hasChild #{c_iri} ."
      end)

    [
      "#{iri} a powl:PartialOrder ;",
      "    rdfs:label \"Partial Order #{id}\" ."
    ] ++ has_children ++ order_triples ++ child_triples
  end

  defp serialize_node(%ChoiceGraph{id: id, children: children, edges: edges}, base_iri) do
    iri = "<#{base_iri}#{id}>"
    child_iris = Enum.map(children, &"<#{base_iri}#{&1.id}>")

    child_triples = Enum.flat_map(children, &serialize_node(&1, base_iri))

    edge_triples =
      Enum.with_index(edges)
      |> Enum.flat_map(fn {{u, v}, idx} ->
        edge_iri = "<#{base_iri}#{id}/edge_#{idx}>"
        u_str = format_edge_node(u, child_iris, base_iri, id)
        v_str = format_edge_node(v, child_iris, base_iri, id)

        [
          "#{iri} powl:hasEdge #{edge_iri} .",
          "#{edge_iri} a powl:Edge ;",
          "    powl:sourceNode #{u_str} ;",
          "    powl:targetNode #{v_str} ."
        ]
      end)

    has_children =
      Enum.map(child_iris, fn c_iri ->
        "#{iri} powl:hasChild #{c_iri} ."
      end)

    [
      "#{iri} a powl:ChoiceGraph ;",
      "    rdfs:label \"Choice Graph #{id}\" ."
    ] ++ has_children ++ edge_triples ++ child_triples
  end

  defp format_edge_node(:start, _children, base_iri, id), do: "<#{base_iri}#{id}/start>"
  defp format_edge_node(:end, _children, base_iri, id), do: "<#{base_iri}#{id}/end>"
  defp format_edge_node(idx, children, _base_iri, _id) when is_integer(idx), do: Enum.at(children, idx)
end
