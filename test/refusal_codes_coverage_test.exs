# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefusalCodesCoverageTest do
  @moduledoc """
  One real trigger per refusal code that previously had no direct test:
  REFUSED_AMBIGUOUS_RELATIONSHIP, REFUSED_UNKNOWN_ATTRIBUTE, REFUSED_INVALID_TERM_MAP,
  UNSUPPORTED_TERM_TYPE, REFUSED_INVALID_FEDERATION_ENVIRONMENT,
  REFUSED_UNPROVEN_EQUIVALENCE, REFUSED_UNSUPPORTED_SPARQL_FEATURE.

  DSL-compile emitters (resource.ex Persist transformer) surface only the refusal detail
  inside a compile-time exception, so those cases assert the detail substring on the
  raised message; every other case asserts the exact `%Refusal{code: ...}`.
  """
  use ExUnit.Case, async: true

  alias AshR2RML.Introspection
  alias AshR2RML.Mapping
  alias AshR2RML.Refusal

  defmodule PlainThing do
    use Ash.Resource, domain: nil, data_layer: Ash.DataLayer.Ets

    attributes do
      uuid_primary_key :id
      attribute :name, :string, public?: true
    end

    actions do
      defaults [:read]
    end
  end

  defp compile_error_message(source) do
    Code.compile_string(source)
    flunk("expected compilation to fail")
  rescue
    exception in ExUnit.AssertionError -> reraise exception, __STACKTRACE__
    exception -> Exception.message(exception)
  end

  defp resource_source(name, r2rml_body) do
    """
    defmodule AshR2RML.RefusalCoverage.#{name} do
      use Ash.Resource,
        domain: nil,
        data_layer: Ash.DataLayer.Ets,
        extensions: [AshR2RML.Resource]

      attributes do
        uuid_primary_key :id
        attribute :name, :string, public?: true
      end

      actions do
        defaults [:read]
      end

      r2rml do
        table_name("things")
        class("https://schema.org/Thing")

        subject do
          template("urn:uuid:{id}")
        end

    #{r2rml_body}
      end
    end
    """
  end

  defp base_resource(overrides) do
    struct!(
      %Mapping.Resource{
        ash_resource: :CoverageRes,
        logical_table: %Mapping.LogicalTable{table_name: "items"},
        class_iris: ["https://schema.org/Thing"],
        subject_map: %Mapping.SubjectMap{strategy: :template, value: "urn:uuid:{id}", term_type: :iri},
        identities: [[:id]],
        metadata: %{attribute_columns: %{id: "id", name: "name"}}
      },
      overrides
    )
  end

  defp refusals(result), do: flatten_refusals(result)

  defp flatten_refusals(%Refusal{} = r), do: [r]
  defp flatten_refusals(t) when is_tuple(t), do: t |> Tuple.to_list() |> flatten_refusals()
  defp flatten_refusals(l) when is_list(l), do: Enum.flat_map(l, &flatten_refusals/1)
  defp flatten_refusals(_), do: []

  defp refusal_with(list, code, substring) do
    Enum.find(list, fn r -> r.code == code and String.contains?(r.detail, substring) end)
  end

  describe "REFUSED_AMBIGUOUS_RELATIONSHIP" do
    test "Introspection.relationship refuses a relationship the Ash resource does not declare" do
      assert {:error, %Refusal{code: :REFUSED_AMBIGUOUS_RELATIONSHIP} = refusal} =
               Introspection.relationship(PlainThing, :ghost)

      assert refusal.detail =~ "Ash relationship does not exist"
      assert refusal.subject == {PlainThing, :ghost}
    end

    test "DSL compile refuses a reference to an undeclared relationship" do
      source =
        resource_source(
          "AmbiguousRel",
          ~s|    property(:name, "https://schema.org/name")\n    reference(:ghost, "https://schema.org/knows")|
        )

      assert compile_error_message(source) =~ "Ash relationship does not exist"
    end
  end

  describe "REFUSED_UNKNOWN_ATTRIBUTE" do
    test "DSL compile refuses a property on an unknown attribute" do
      source = resource_source("UnknownAttr", ~s|    property(:ghost_attr, "https://schema.org/alternateName")|)

      assert compile_error_message(source) =~ "unknown Ash attribute"
    end
  end

  describe "REFUSED_INVALID_TERM_MAP" do
    test "DSL compile refuses a language tag on a non-literal term map" do
      source =
        resource_source(
          "LangIri",
          ~s|    property(:name, "https://schema.org/name", language: "en", term_type: :iri)|
        )

      assert compile_error_message(source) =~ "language-tagged values must be literal term maps"
    end

    test "Mapping.validate refuses an unsupported subject strategy" do
      mapping =
        base_resource(subject_map: %Mapping.SubjectMap{strategy: :bogus, value: "urn:uuid:{id}", term_type: :iri})

      found =
        refusal_with(refusals(Mapping.validate(mapping)), :REFUSED_INVALID_TERM_MAP, "unsupported subject strategy")

      assert %Refusal{evidence: %{strategy: :bogus}} = found
    end

    test "Mapping.validate refuses an empty object map value" do
      mapping =
        base_resource(
          predicate_object_maps: [
            %Mapping.PredicateObjectMap{
              attribute: :name,
              predicate_iri: "https://schema.org/name",
              object_map: %Mapping.ObjectMap{strategy: :column, value: "", term_type: :literal}
            }
          ]
        )

      assert refusal_with(
               refusals(Mapping.validate(mapping)),
               :REFUSED_INVALID_TERM_MAP,
               "object map value must be non-empty"
             )
    end
  end

  describe "UNSUPPORTED_TERM_TYPE" do
    test "Mapping.validate refuses an unsupported subject term type" do
      mapping =
        base_resource(
          subject_map: %Mapping.SubjectMap{
            strategy: :template,
            value: "urn:uuid:{id}",
            term_type: :literal
          }
        )

      found = refusal_with(refusals(Mapping.validate(mapping)), :UNSUPPORTED_TERM_TYPE, "unsupported subject term type")
      assert %Refusal{evidence: %{term_type: :literal}} = found
    end

    test "Mapping.validate refuses an unsupported object term type" do
      mapping =
        base_resource(
          predicate_object_maps: [
            %Mapping.PredicateObjectMap{
              attribute: :name,
              predicate_iri: "https://schema.org/name",
              object_map: %Mapping.ObjectMap{strategy: :column, value: "name", term_type: :bogus}
            }
          ]
        )

      assert refusal_with(refusals(Mapping.validate(mapping)), :UNSUPPORTED_TERM_TYPE, "unsupported object term type")
    end

    test "renderer refuses a many_to_many bridge over a blank-node subject strategy" do
      source =
        base_resource(
          ash_resource: AshR2RML.GrandExample.Person,
          logical_table: %Mapping.LogicalTable{table_name: "sources"},
          class_iris: ["https://schema.org/Thing"],
          subject_map: %Mapping.SubjectMap{strategy: :blank_node, value: "src", term_type: :blank_node},
          reference_object_maps: [
            %Mapping.ReferenceObjectMap{
              relationship: :targets,
              predicate_iri: "https://schema.org/knows",
              parent_resource: AshR2RML.GrandExample.Organization,
              metadata: %{
                kind: :many_to_many,
                through_logical_table: %Mapping.LogicalTable{table_name: "links"},
                source_to_join: %Mapping.JoinCondition{child: "id", parent: "source_id"},
                join_to_destination: %Mapping.JoinCondition{child: "target_id", parent: "id"}
              }
            }
          ]
        )

      target =
        base_resource(
          ash_resource: AshR2RML.GrandExample.Organization,
          logical_table: %Mapping.LogicalTable{table_name: "targets"},
          class_iris: ["https://schema.org/Thing"],
          subject_map: %Mapping.SubjectMap{strategy: :template, value: "urn:uuid:{id}", term_type: :iri}
        )

      assert {:error, %Refusal{code: :UNSUPPORTED_TERM_TYPE} = refusal} =
               AshR2RML.R2RML.render(%Mapping.Bundle{resources: [source, target]})

      assert refusal.detail =~ "unsupported for many_to_many bridge"
      assert refusal.evidence == %{strategy: :blank_node}
    end
  end

  describe "REFUSED_INVALID_FEDERATION_ENVIRONMENT" do
    @query "SELECT * WHERE { ?s ?p ?o }"

    test "refuses a non-http scheme" do
      assert {:error, %Refusal{code: :REFUSED_INVALID_FEDERATION_ENVIRONMENT} = refusal} =
               AshR2RML.SPARQL.Protocol.query("ftp://127.0.0.1/sparql", @query)

      assert refusal.detail =~ "http or https"
    end

    test "refuses an http URL with an empty host" do
      assert {:error, %Refusal{code: :REFUSED_INVALID_FEDERATION_ENVIRONMENT}} =
               AshR2RML.SPARQL.Protocol.query("http:///sparql", @query)
    end
  end

  describe "REFUSED_UNPROVEN_EQUIVALENCE" do
    test "Query.admit refuses a non-query term" do
      assert {:error, %Refusal{code: :REFUSED_UNPROVEN_EQUIVALENCE} = refusal} =
               AshR2RML.SPARQL.Query.admit(12_345)

      assert refusal.detail =~ "expected SPARQL query text"
    end

    test "Query.admit refuses text that is not SPARQL" do
      assert {:error, %Refusal{code: :REFUSED_UNPROVEN_EQUIVALENCE} = refusal} =
               AshR2RML.SPARQL.Query.admit("this is definitely not sparql")

      assert refusal.detail =~ "language admission"
    end

    test "Query.load_file refuses an unreadable path" do
      path = Path.join(System.tmp_dir!(), "ash_r2rml_missing_#{System.unique_integer([:positive])}.rq")

      assert {:error, %Refusal{code: :REFUSED_UNPROVEN_EQUIVALENCE} = refusal} =
               AshR2RML.SPARQL.Query.load_file(path)

      assert refusal.detail =~ "failed to read SPARQL file"
    end

    test "Local.query refuses a valid query over data SPARQL.ex cannot execute against" do
      assert {:error, %Refusal{code: :REFUSED_UNPROVEN_EQUIVALENCE} = refusal} =
               AshR2RML.SPARQL.Local.query(:not_rdf_data, "SELECT * WHERE { ?s ?p ?o }")

      assert refusal.detail =~ "could not execute"
    end

    test "Mapping.validate refuses a relative inverse predicate" do
      mapping =
        base_resource(
          reference_object_maps: [
            %Mapping.ReferenceObjectMap{
              relationship: :owner,
              predicate_iri: "https://schema.org/author",
              inverse_predicate: "relative-inverse",
              parent_resource: :CoverageRes,
              joins: [%Mapping.JoinCondition{child: "id", parent: "id"}]
            }
          ]
        )

      assert refusal_with(
               refusals(Mapping.validate(mapping)),
               :REFUSED_UNPROVEN_EQUIVALENCE,
               "inverse predicate must be an absolute IRI"
             )
    end
  end

  describe "REFUSED_UNSUPPORTED_SPARQL_FEATURE" do
    test "in-memory materialization refuses a constant subject strategy before reading any row" do
      mapping =
        base_resource(
          ash_resource: PlainThing,
          subject_map: %Mapping.SubjectMap{
            strategy: :constant,
            value: "urn:uuid:00000000-0000-0000-0000-000000000001",
            term_type: :iri
          }
        )

      assert {:error, %Refusal{code: :REFUSED_UNSUPPORTED_SPARQL_FEATURE} = refusal} =
               AshR2RML.OBDA.InMemory.materialize(PlainThing, mapping)

      assert refusal.detail =~ "only supports :template and :column"
      assert refusal.evidence == %{strategy: :constant}
    end
  end

  describe "Error catalog completeness" do
    @lib Path.expand("../lib", __DIR__)

    defp source_codes do
      @lib
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.reject(&(Path.basename(&1) == "error.ex"))
      |> Enum.flat_map(fn path ->
        ~r/\b(?:REFUSED|UNSUPPORTED)_[A-Z0-9_]+\b/
        |> Regex.scan(File.read!(path))
        |> Enum.map(fn [code] -> {String.to_atom(code), Path.relative_to(path, @lib)} end)
      end)
    end

    test "the scan is not vacuous" do
      codes = source_codes()
      assert length(codes) > 50
      assert Enum.any?(codes, fn {c, _} -> c == :REFUSED_READ_FAILED end)
      assert Enum.any?(codes, fn {c, _} -> c == :REFUSED_RESOURCE_BOUND end)
    end

    test "every code named in lib/ is in AshR2RML.Error's catalog" do
      catalog = AshR2RML.Error.codes()

      missing =
        source_codes()
        |> Enum.reject(fn {code, _} -> code in catalog end)
        |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

      assert missing == %{},
             "codes emitted or referenced in lib/ but missing from the Error catalog: " <>
               inspect(Map.new(missing, fn {c, files} -> {c, Enum.uniq(files)} end))
    end

    test "every catalog code is emitted or referenced somewhere in lib/ outside error.ex" do
      used = source_codes() |> Enum.map(&elem(&1, 0)) |> MapSet.new()
      stale = Enum.reject(AshR2RML.Error.codes(), &MapSet.member?(used, &1))
      assert stale == [], "catalog codes no emitter references: #{inspect(stale)}"
    end
  end
end
