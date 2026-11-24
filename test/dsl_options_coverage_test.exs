# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.DslOptionsCoverageTest do
  @moduledoc """
  Real Ash resources (ETS) exercising DSL options that no other suite pins.
  Every assertion is on the compiled mapping IR, the rendered R2RML Turtle, or the
  typed result of the real in-memory materializer -- never on interactions.
  """
  use ExUnit.Case, async: true

  alias AshR2RML.Mapping.{GraphMap, ObjectMap, PredicateObjectMap, ReferenceObjectMap, SubjectMap}
  alias AshR2RML.OBDA.InMemory
  alias AshR2RML.Resource.Info

  @rdf_type "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"

  defmodule ConstSubject do
    use Ash.Resource, domain: nil, data_layer: Ash.DataLayer.Ets, extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :name, :string, public?: true
    end

    r2rml do
      table_name("const_subjects")
      class("https://example.test/Singleton")

      subject do
        constant("https://example.test/thing/the-one")
      end

      property(:name, "https://schema.org/name")
    end
  end

  defmodule BNodeTemplated do
    use Ash.Resource, domain: nil, data_layer: Ash.DataLayer.Ets, extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :name, :string, public?: true
    end

    r2rml do
      table_name("bnode_templated")
      class("https://example.test/Anon")

      subject do
        template("anon_{id}")
        term_type(:blank_node)
      end

      property(:name, "https://schema.org/name")
    end
  end

  defmodule BNodeDefault do
    use Ash.Resource, domain: nil, data_layer: Ash.DataLayer.Ets, extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :name, :string, public?: true
    end

    r2rml do
      table_name("bnode_default")
      class("https://example.test/Anon")

      subject do
        term_type(:blank_node)
      end

      property(:name, "https://schema.org/name")
    end
  end

  defmodule PropertyMaps do
    use Ash.Resource, domain: nil, data_layer: Ash.DataLayer.Ets, extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :kind, :string, public?: true
      attribute :slug, :string, public?: true
      attribute :homepage, :string, public?: true
      attribute :anchor, :string, public?: true
      attribute :note, :string, public?: true
      attribute :label, :string, public?: true
      attribute :label_lang, :string, public?: true
    end

    r2rml do
      table_name("property_maps")
      class("https://example.test/PropertyMaps")

      subject do
        template("https://example.test/pm/{id}")
      end

      property(:kind, "https://example.test/kind", constant: "https://example.test/Kind/fixed", term_type: :iri)

      property(:slug, "https://example.test/slugIri", template: "https://example.test/slug/{slug}", term_type: :iri)

      property(:homepage, "https://example.test/homepage", term_type: :iri)
      property(:anchor, "https://example.test/anchor", term_type: :blank_node)
      property(:note, "https://example.test/note", constant: "fixed")
      property(:label, "https://example.test/label", language_column: :label_lang)
    end
  end

  defmodule GraphSubject do
    use Ash.Resource, domain: nil, data_layer: Ash.DataLayer.Ets, extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :name, :string, public?: true
    end

    r2rml do
      table_name("graph_subjects")
      class("https://example.test/Graphed")

      subject do
        template("https://example.test/graphed/{id}")
      end

      graph("https://example.test/graph/g1", scope: :subject)
      property(:name, "https://schema.org/name")
    end
  end

  defmodule Parent do
    use Ash.Resource, domain: nil, data_layer: Ash.DataLayer.Ets, extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :name, :string, public?: true
    end

    r2rml do
      table_name("parents")
      class("https://example.test/Parent")

      subject do
        template("https://example.test/parent/{id}")
      end

      property(:name, "https://schema.org/name")
    end
  end

  defmodule Child do
    use Ash.Resource, domain: nil, data_layer: Ash.DataLayer.Ets, extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
    end

    relationships do
      belongs_to :parent, AshR2RML.DslOptionsCoverageTest.Parent, allow_nil?: false, public?: true
    end

    r2rml do
      table_name("children")
      class("https://example.test/Child")

      subject do
        template("https://example.test/child/{id}")
      end

      reference(:parent, "https://example.test/hasParent",
        direction: :incoming,
        guard_class: "https://example.test/Guard",
        inverse_predicate: "https://example.test/hasChild"
      )
    end
  end

  defmodule QueryForms do
    use Ash.Resource, domain: nil, data_layer: Ash.DataLayer.Ets, extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :name, :string, public?: true
    end

    r2rml do
      table_name("query_forms")
      class("https://example.test/Queried")

      subject do
        template("https://example.test/queried/{id}")
      end

      property(:name, "https://schema.org/name")
    end

    sparql do
      query :build_names do
        form(:construct)
        where [{:s, "https://schema.org/name", :n}]
      end

      query :describe_queried do
        form(:describe)
        where [{:s, "http://www.w3.org/1999/02/22-rdf-syntax-ns#type", "https://example.test/Queried"}]
      end
    end
  end

  defp map_name(module), do: "#" <> (module |> Module.split() |> Enum.join("_"))

  defp property!(mapping, attribute) do
    Enum.find(mapping.predicate_object_maps, &(&1.attribute == attribute)) ||
      flunk("no predicate object map for #{inspect(attribute)}")
  end

  test "subject constant: compiles to a constant IRI subject map and renders rr:constant" do
    mapping = Info.mapping!(ConstSubject)

    assert %SubjectMap{strategy: :constant, value: "https://example.test/thing/the-one", term_type: :iri} =
             mapping.subject_map

    assert AshR2RML.Mapping.stable_subject_identity?(mapping)

    assert {:ok, ttl} = AshR2RML.render_r2rml(ConstSubject)

    assert ttl =~
             ~s(rr:subjectMap [ rr:constant <https://example.test/thing/the-one>; rr:class <https://example.test/Singleton> ])
  end

  test "constant subject is refused by the in-memory materializer with a typed refusal" do
    mapping = Info.mapping!(ConstSubject)

    assert {:error, %AshR2RML.Refusal{code: :REFUSED_UNSUPPORTED_SPARQL_FEATURE, evidence: %{strategy: :constant}}} =
             InMemory.materialize(ConstSubject, mapping)
  end

  test "property constant: with term_type :iri compiles to a constant IRI object map" do
    mapping = Info.mapping!(PropertyMaps)

    assert %PredicateObjectMap{
             predicate_iri: "https://example.test/kind",
             object_map: %ObjectMap{
               strategy: :constant,
               value: "https://example.test/Kind/fixed",
               term_type: :iri,
               datatype: nil,
               language: nil
             }
           } = property!(mapping, :kind)

    assert {:ok, ttl} = AshR2RML.render_r2rml(PropertyMaps)

    assert ttl =~
             ~s(rr:predicateObjectMap [ rr:predicate <https://example.test/kind>; rr:objectMap [ rr:constant <https://example.test/Kind/fixed>; rr:termType rr:IRI ] ])
  end

  test "property constant: literal keeps the constant strategy and a literal term type" do
    mapping = Info.mapping!(PropertyMaps)

    assert %ObjectMap{strategy: :constant, value: "fixed", term_type: :literal} =
             property!(mapping, :note).object_map

    assert {:ok, ttl} = AshR2RML.render_r2rml(PropertyMaps)
    assert ttl =~ ~s(rr:predicate <https://example.test/note>; rr:objectMap [ rr:constant "fixed")
  end

  test "property template: with term_type :iri compiles to a template object map" do
    mapping = Info.mapping!(PropertyMaps)

    assert %ObjectMap{strategy: :template, value: "https://example.test/slug/{slug}", term_type: :iri} =
             property!(mapping, :slug).object_map

    assert {:ok, ttl} = AshR2RML.render_r2rml(PropertyMaps)

    assert ttl =~
             ~s(rr:predicate <https://example.test/slugIri>; rr:objectMap [ rr:template "https://example.test/slug/{slug}"; rr:termType rr:IRI ])
  end

  test "property term_type :iri over a column renders the column as an IRI" do
    mapping = Info.mapping!(PropertyMaps)

    assert %ObjectMap{strategy: :column, value: "homepage", term_type: :iri, datatype: nil} =
             property!(mapping, :homepage).object_map

    assert {:ok, ttl} = AshR2RML.render_r2rml(PropertyMaps)

    assert ttl =~
             ~s(rr:predicate <https://example.test/homepage>; rr:objectMap [ rr:column "homepage"; rr:termType rr:IRI ])
  end

  test "property term_type :blank_node over a column renders rr:BlankNode" do
    mapping = Info.mapping!(PropertyMaps)

    assert %ObjectMap{strategy: :column, value: "anchor", term_type: :blank_node, datatype: nil} =
             property!(mapping, :anchor).object_map

    assert {:ok, ttl} = AshR2RML.render_r2rml(PropertyMaps)

    assert ttl =~
             ~s(rr:predicate <https://example.test/anchor>; rr:objectMap [ rr:column "anchor"; rr:termType rr:BlankNode ])
  end

  test "property language_column: records the language column on a literal and renders rr:language" do
    mapping = Info.mapping!(PropertyMaps)

    assert %ObjectMap{strategy: :column, value: "label", language: "label_lang", term_type: :literal, datatype: nil} =
             property!(mapping, :label).object_map

    assert {:ok, ttl} = AshR2RML.render_r2rml(PropertyMaps)

    assert ttl =~
             ~s(rr:predicate <https://example.test/label>; rr:objectMap [ rr:column "label"; rr:language "label_lang" ])
  end

  test "subject term_type :blank_node with a template renders blank-node subjects" do
    mapping = Info.mapping!(BNodeTemplated)

    assert %SubjectMap{strategy: :blank_node, value: "anon_{id}", term_type: :blank_node} = mapping.subject_map

    assert {:ok, ttl} = AshR2RML.render_r2rml(BNodeTemplated)

    assert ttl =~
             ~s(rr:subjectMap [ rr:template "anon_{id}"; rr:class <https://example.test/Anon>; rr:termType rr:BlankNode ])
  end

  test "subject term_type :blank_node without a template defaults to bnode_{id}" do
    mapping = Info.mapping!(BNodeDefault)

    assert %SubjectMap{strategy: :blank_node, value: "bnode_{id}", term_type: :blank_node} = mapping.subject_map

    assert {:ok, ttl} = AshR2RML.render_r2rml(BNodeDefault)

    assert ttl =~
             ~s(rr:subjectMap [ rr:template "bnode_{id}"; rr:class <https://example.test/Anon>; rr:termType rr:BlankNode ])
  end

  test "blank-node subject is refused by the in-memory materializer with a typed refusal" do
    mapping = Info.mapping!(BNodeTemplated)

    assert {:error, %AshR2RML.Refusal{code: :REFUSED_UNSUPPORTED_SPARQL_FEATURE, evidence: %{strategy: :blank_node}}} =
             InMemory.materialize(BNodeTemplated, mapping)
  end

  test "graph scope: :subject attaches the graph to the subject map, not the resource" do
    mapping = Info.mapping!(GraphSubject)

    assert mapping.graph_maps == []
    assert [%GraphMap{strategy: :constant, value: "https://example.test/graph/g1"}] = mapping.subject_map.graph_maps

    assert {:ok, ttl} = AshR2RML.render_r2rml(GraphSubject)

    assert ttl =~
             ~s(rr:subjectMap [ rr:template "https://example.test/graphed/{id}"; rr:class <https://example.test/Graphed>; rr:graph <https://example.test/graph/g1> ])
  end

  test "reference direction: :incoming and guard_class are recorded on the reference IR" do
    mapping = Info.mapping!(Child)

    assert [%ReferenceObjectMap{} = reference] = mapping.reference_object_maps
    assert reference.parent_resource == Parent
    assert reference.predicate_iri == "https://example.test/hasParent"
    assert reference.metadata.direction == :incoming
    assert reference.metadata.guard_class == "https://example.test/Guard"
    assert reference.metadata.kind == :belongs_to
    assert [%AshR2RML.Mapping.JoinCondition{child: "parent_id", parent: "id"}] = reference.joins
  end

  test "reference inverse_predicate renders the exact inverse triples map with reversed joins" do
    mapping = Info.mapping!(Child)
    assert [%ReferenceObjectMap{inverse_predicate: "https://example.test/hasChild"}] = mapping.reference_object_maps

    assert {:ok, ttl} = AshR2RML.render_r2rml(Child)

    assert ttl =~
             ~s(rr:predicateObjectMap [ rr:predicate <https://example.test/hasParent>; rr:objectMap [ rr:parentTriplesMap <#{map_name(Parent)}>; rr:joinCondition [ rr:child "parent_id"; rr:parent "id" ] ] ])

    assert ttl =~
             ~s(rr:subjectMap [ rr:template "https://example.test/parent/{id}"; rr:class <https://example.test/Parent> ] ;\n) <>
               ~s(  rr:predicateObjectMap [ rr:predicate <https://example.test/hasChild>; ) <>
               ~s(rr:objectMap [ rr:parentTriplesMap <#{map_name(Child)}>; rr:joinCondition [ rr:child "id"; rr:parent "parent_id" ] ] ] .)
  end

  test "sparql query forms :construct and :describe are recorded on the compiled resource" do
    queries = Info.sparql_queries(QueryForms)

    assert [
             %AshR2RML.Dsl.SparqlQuery{name: :build_names, form: :construct, select: [], where: construct_where},
             %AshR2RML.Dsl.SparqlQuery{name: :describe_queried, form: :describe, select: [], where: describe_where}
           ] = queries

    assert construct_where == [{:s, "https://schema.org/name", :n}]
    assert describe_where == [{:s, @rdf_type, "https://example.test/Queried"}]
  end
end
