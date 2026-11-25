# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.MappingValidationGapsTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Mapping
  alias AshR2RML.Mapping.{Datatype, GraphMap, LogicalTable, ObjectMap, PredicateObjectMap, ReferenceObjectMap}
  alias AshR2RML.Mapping.{JoinCondition, Resource, SubjectMap}

  @class "https://example.test/Thing"
  @pred "https://example.test/name"
  @xsd "http://www.w3.org/2001/XMLSchema#string"

  defp base(opts) do
    %Resource{
      ash_resource: "Thing",
      class_iris: Keyword.get(opts, :class_iris, [@class]),
      logical_table: %LogicalTable{table_name: "things"},
      subject_map:
        Keyword.get(opts, :subject_map, %SubjectMap{
          strategy: :template,
          value: "https://example.test/things/{id}",
          term_type: :iri
        }),
      identities: [[:id]],
      predicate_object_maps: Keyword.get(opts, :pom, []),
      reference_object_maps: Keyword.get(opts, :refs, []),
      graph_maps: Keyword.get(opts, :graph_maps, []),
      metadata: %{attribute_columns: %{id: "id", name: "name"}}
    }
  end

  defp pom(object, opts \\ []) do
    %PredicateObjectMap{
      attribute: Keyword.get(opts, :attribute, :name),
      predicate_iri: Keyword.get(opts, :predicate, @pred),
      object_map: object
    }
  end

  defp codes({:error, refusals}), do: Enum.map(refusals, & &1.code)
  defp codes(:ok), do: []

  describe "1. object template placeholders" do
    test "refuses placeholder absent from available columns" do
      obj = %ObjectMap{strategy: :template, value: "x-{ghost}"}
      assert :REFUSED_INVALID_TERM_MAP in codes(Mapping.validate(base(pom: [pom(obj)])))
    end

    test "positive control: placeholder naming an existing column validates" do
      obj = %ObjectMap{strategy: :template, value: "x-{name}"}
      assert :ok = Mapping.validate(base(pom: [pom(obj)]))
    end
  end

  describe "2. constant IRI object map" do
    test "refuses relative constant IRI" do
      obj = %ObjectMap{strategy: :constant, value: "relative/path", term_type: :iri}
      assert :REFUSED_INVALID_TERM_MAP in codes(Mapping.validate(base(pom: [pom(obj)])))
    end

    test "positive control: absolute constant IRI validates" do
      obj = %ObjectMap{strategy: :constant, value: "https://example.test/v", term_type: :iri}
      assert :ok = Mapping.validate(base(pom: [pom(obj)]))
    end
  end

  describe "3. language + datatype" do
    test "refuses both on one struct" do
      obj = %ObjectMap{
        strategy: :column,
        value: "name",
        language: "en",
        datatype: %Datatype{rdf_datatype: @xsd}
      }

      assert :REFUSED_INVALID_TERM_MAP in codes(Mapping.validate(base(pom: [pom(obj)])))
    end

    test "positive control: language alone and datatype alone validate" do
      lang = %ObjectMap{strategy: :column, value: "name", language: "en"}
      typed = %ObjectMap{strategy: :column, value: "name", datatype: %Datatype{rdf_datatype: @xsd}}
      assert :ok = Mapping.validate(base(pom: [pom(lang)]))
      assert :ok = Mapping.validate(base(pom: [pom(typed)]))
    end
  end

  describe "4. duplicates" do
    test "refuses duplicate (attribute, predicate) property maps" do
      obj = %ObjectMap{strategy: :column, value: "name"}
      result = Mapping.validate(base(pom: [pom(obj), pom(obj)]))
      assert :REFUSED_INVALID_TERM_MAP in codes(result)
    end

    test "positive control: same attribute with different predicates validates" do
      obj = %ObjectMap{strategy: :column, value: "name"}
      other = pom(obj, predicate: "https://example.test/label")
      assert :ok = Mapping.validate(base(pom: [pom(obj), other]))
    end

    defp ref(predicate) do
      %ReferenceObjectMap{
        relationship: :owner,
        predicate_iri: predicate,
        parent_resource: "Owner",
        joins: [%JoinCondition{child: "id", parent: "id"}]
      }
    end

    test "refuses duplicate (relationship, predicate) references" do
      result = Mapping.validate(base(refs: [ref(@pred), ref(@pred)]))
      assert :REFUSED_AMBIGUOUS_RELATIONSHIP in codes(result)
    end

    test "positive control: distinct predicates do not trip the duplicate check" do
      result = Mapping.validate(base(refs: [ref(@pred), ref("https://example.test/other")]))
      refute :REFUSED_AMBIGUOUS_RELATIONSHIP in codes(result)
    end
  end

  describe "5. blank-node subject template" do
    defp blank(value), do: %SubjectMap{strategy: :blank_node, value: value, term_type: :blank_node}

    test "refuses blank-node template referencing a missing column" do
      assert :REFUSED_MISSING_SUBJECT_MAP in codes(Mapping.validate(base(subject_map: blank("b-{ghost}"))))
    end

    test "positive control: blank-node template over an existing column validates" do
      assert :ok = Mapping.validate(base(subject_map: blank("b-{id}")))
    end
  end

  describe "6. IRIREF characters" do
    test "refuses forbidden characters in class, predicate, graph, datatype and constants" do
      for ch <- [" ", "<", ">", "\"", "{", "}", "|", "^", "`", "\\", "\n", <<0>>] do
        bad = "https://example.test/a" <> ch <> "b"
        obj = %ObjectMap{strategy: :column, value: "name"}

        assert :REFUSED_INVALID_CLASS_IRI in codes(Mapping.validate(base(class_iris: [bad]))), inspect(ch)

        assert :REFUSED_RELATIONSHIP_WITHOUT_PREDICATE in codes(Mapping.validate(base(pom: [pom(obj, predicate: bad)]))),
               inspect(ch)

        gm = [%GraphMap{strategy: :constant, value: bad}]
        assert :REFUSED_INVALID_GRAPH_MAP in codes(Mapping.validate(base(graph_maps: gm))), inspect(ch)

        dt = %ObjectMap{strategy: :column, value: "name", datatype: %Datatype{rdf_datatype: bad}}
        assert :REFUSED_UNMAPPED_DATATYPE in codes(Mapping.validate(base(pom: [pom(dt)]))), inspect(ch)

        const = %ObjectMap{strategy: :constant, value: bad, term_type: :iri}
        assert :REFUSED_INVALID_TERM_MAP in codes(Mapping.validate(base(pom: [pom(const)]))), inspect(ch)
      end
    end

    test "positive control: clean absolute IRIs with percent-encoding validate" do
      iri = "https://example.test/a%20b?q=1#frag"
      gm = [%GraphMap{strategy: :constant, value: iri}]
      assert :ok = Mapping.validate(base(class_iris: [iri], graph_maps: gm))
    end
  end

  describe "7. introspection logical_table" do
    alias AshR2RML.Introspection

    test "whitespace-only table_name with sql_query counts as absent" do
      assert {:ok, %LogicalTable{sql_query: "select 1", table_name: nil}} =
               Introspection.logical_table(Thing, table_name: "   ", sql_query: "select 1")
    end

    test "whitespace-only sql_query with table_name counts as absent" do
      assert {:ok, %LogicalTable{table_name: "t", sql_query: nil}} =
               Introspection.logical_table(Thing, table_name: "t", sql_query: " \t")
    end

    test "schema combined with sql_query refuses" do
      assert {:error, %AshR2RML.Refusal{code: :REFUSED_INVALID_LOGICAL_TABLE}} =
               Introspection.logical_table(Thing, sql_query: "select 1", schema: "public")
    end

    test "positive control: schema with table_name is kept" do
      assert {:ok, %LogicalTable{table_name: "t", schema: "public"}} =
               Introspection.logical_table(Thing, table_name: "t", schema: "public")
    end

    test "both table_name and sql_query non-blank still refuses" do
      assert {:error, %AshR2RML.Refusal{code: :REFUSED_INVALID_LOGICAL_TABLE}} =
               Introspection.logical_table(Thing, table_name: "t", sql_query: "select 1")
    end
  end
end
