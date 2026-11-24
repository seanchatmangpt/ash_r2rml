# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.ApiSurfaceCoverageTest do
  # async: false because the GenerateDocs test changes the process working directory.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias AshR2RML.{CompilationReceipt, Compiler, DataLayer, Introspection, Refusal}
  alias AshR2RML.GrandExample.{Organization, Person, Shipment, Warehouse}

  alias AshR2RML.Mapping
  alias AshR2RML.Mapping.{Bundle, GraphMap, JoinCondition, LogicalTable, Resource, SubjectMap}

  defp receipt!, do: AshR2RML.validate([Person])

  defp hand_resource(overrides \\ []) do
    base = %Resource{
      ash_resource: "urn:test:A",
      logical_table: %LogicalTable{table_name: "a"},
      subject_map: %SubjectMap{strategy: :template, value: "https://ex.org/a/{id}"},
      class_iris: ["https://ex.org/A"],
      identities: [[:id]],
      metadata: %{attribute_columns: %{id: "id"}}
    }

    struct!(base, overrides)
  end

  describe "AshR2RML.validate/1 and AshR2RML.Validation" do
    test "admits Person with its closed Organization dependency" do
      receipt = receipt!()

      assert %CompilationReceipt{
               status: :PARTIAL_ALIVE,
               standing: :constructed_not_actuated,
               query_parity: :UNKNOWN,
               cutover_authority: :UNAUTHORIZED,
               classes_admitted: 2,
               executed: [:canonical_mapping_ir, :r2rml_render],
               verified: [:canonical_mapping_ir_projection],
               blocked: [:sparql_sql_behavioral_parity, :cutover_authority],
               refusals: []
             } = receipt

      assert receipt.mapping_sha256 =~ ~r/\A[0-9a-f]{64}\z/
      assert receipt.r2rml_sha256 =~ ~r/\A[0-9a-f]{64}\z/
      assert receipt.mapping_sha256 == AshR2RML.validate([Person]).mapping_sha256
      assert AshR2RML.Validation.cutover_ready?(receipt) == false
    end

    test "refuses a resource with no mapping" do
      assert %CompilationReceipt{
               status: :REFUSED,
               standing: :no_cutover,
               refusals: [%Refusal{code: :REFUSED_MISSING_SUBJECT_MAP, subject: Warehouse}]
             } = AshR2RML.validate([Warehouse])
    end
  end

  describe "Compiler" do
    test "compile/2 returns a dependency-closed, normalized bundle" do
      assert {:ok, %Bundle{resources: resources}} = Compiler.compile([Person], [])
      assert resources |> Enum.map(& &1.ash_resource) |> Enum.sort() == [Organization, Person]
      assert Compiler.compile(Person) == Compiler.compile([Person])
    end

    test "compile/2 returns a typed refusal for an unmapped resource" do
      assert {:error, %Refusal{code: :REFUSED_MISSING_SUBJECT_MAP}} = Compiler.compile([Warehouse])
    end

    test "sha256/1 is deterministic and hex encoded" do
      assert Compiler.sha256("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
      assert Compiler.sha256(%{a: 1}) == Compiler.sha256(%{a: 1})
      refute Compiler.sha256(%{a: 1}) == Compiler.sha256(%{a: 2})
    end

    test "cutover_ready?/1 is false for anything but a verified and authorized receipt" do
      refute Compiler.cutover_ready?(receipt!())
      refute Compiler.cutover_ready?(:not_a_receipt)

      assert Compiler.cutover_ready?(%CompilationReceipt{
               query_parity: :VERIFIED,
               cutover_authority: :AUTHORIZED,
               blocked: []
             })

      refute Compiler.cutover_ready?(%CompilationReceipt{
               query_parity: :VERIFIED,
               cutover_authority: :AUTHORIZED,
               blocked: [:something]
             })
    end

    test "valid sparql_sql witness clears the parity block and records the witness" do
      out = Compiler.attach_parity_witness(receipt!(), :sparql_sql, %{verified?: true, receipt_sha256: "abc123"})

      assert out.query_parity == :VERIFIED
      assert out.blocked == [:cutover_authority]
      assert {:parity_witness, :sparql_sql, "abc123"} in out.verified
      assert out.refusals == []
    end

    test "string-keyed witness is accepted" do
      out = Compiler.attach_parity_witness(receipt!(), :sparql_sql, %{"verified?" => true, "receipt_sha256" => "ff"})
      assert out.query_parity == :VERIFIED
    end

    test "invalid sparql_sql witnesses append REFUSED_UNPROVEN_EQUIVALENCE" do
      base = receipt!()

      for witness <- [
            %{},
            %{verified?: true},
            %{verified?: true, receipt_sha256: ""},
            %{verified?: false, receipt_sha256: "abc"}
          ] do
        out = Compiler.attach_parity_witness(base, :sparql_sql, witness)

        assert out.query_parity == :UNKNOWN
        assert out.blocked == base.blocked
        assert [%Refusal{code: :REFUSED_UNPROVEN_EQUIVALENCE, subject: :sparql_sql}] = out.refusals
      end
    end

    test "refusals accumulate across repeated invalid witnesses" do
      out =
        receipt!()
        |> Compiler.attach_parity_witness(:sparql_sql, %{})
        |> Compiler.attach_parity_witness(:neo4j_postgres, %{})

      assert [
               %Refusal{code: :REFUSED_UNPROVEN_EQUIVALENCE, subject: :neo4j_postgres},
               %Refusal{code: :REFUSED_UNPROVEN_EQUIVALENCE, subject: :sparql_sql}
             ] = out.refusals
    end

    test "neo4j_postgres witness valid and invalid" do
      ok = Compiler.attach_parity_witness(receipt!(), :neo4j_postgres, %{verified?: true, receipt_sha256: "n4j"})
      assert ok.neo4j_postgres_parity == :VERIFIED
      assert {:parity_witness, :neo4j_postgres, "n4j"} in ok.verified
      assert ok.query_parity == :UNKNOWN

      bad = Compiler.attach_parity_witness(receipt!(), :neo4j_postgres, %{verified?: true})
      assert bad.neo4j_postgres_parity == nil
      assert [%Refusal{code: :REFUSED_UNPROVEN_EQUIVALENCE}] = bad.refusals
    end

    test "authorize_cutover/2 with a valid authority plus parity yields cutover_ready?" do
      out =
        receipt!()
        |> Compiler.attach_parity_witness(:sparql_sql, %{verified?: true, receipt_sha256: "p"})
        |> Compiler.authorize_cutover(%{authorized?: true, receipt_sha256: "auth1"})

      assert out.cutover_authority == :AUTHORIZED
      assert out.blocked == []
      assert {:cutover_authority, "auth1"} in out.verified
      assert Compiler.cutover_ready?(out)
      assert AshR2RML.Validation.cutover_ready?(out)
    end

    test "authorize_cutover/2 alone does not grant cutover while parity is blocked" do
      out = Compiler.authorize_cutover(receipt!(), %{"authorized?" => true, "receipt_sha256" => "a"})
      assert out.cutover_authority == :AUTHORIZED
      assert out.query_parity == :UNKNOWN
      refute Compiler.cutover_ready?(out)
    end

    test "authorize_cutover/2 refuses unauthorized or id-less authority" do
      base = receipt!()

      for authority <- [%{}, %{authorized?: false, receipt_sha256: "x"}, %{authorized?: true}] do
        out = Compiler.authorize_cutover(base, authority)
        assert out.cutover_authority == :UNAUTHORIZED
        assert [%Refusal{code: :REFUSED_UNPROVEN_EQUIVALENCE, subject: :cutover_authority}] = out.refusals
      end
    end
  end

  describe "Mapping" do
    test "normalize/1 sorts and dedupes class iris and identities" do
      resource =
        hand_resource(
          class_iris: ["https://ex.org/B", "https://ex.org/A", "https://ex.org/B"],
          identities: [[:b, :a], [:a, :b], [:id]],
          graph_maps: [
            %GraphMap{strategy: :constant, value: "https://ex.org/g2"},
            %GraphMap{strategy: :constant, value: "https://ex.org/g1"},
            %GraphMap{strategy: :constant, value: "https://ex.org/g1"}
          ]
        )

      normalized = Mapping.normalize(resource)
      assert normalized.class_iris == ["https://ex.org/A", "https://ex.org/B"]
      assert normalized.identities == [[:a, :b], [:id]]
      assert Enum.map(normalized.graph_maps, & &1.value) == ["https://ex.org/g1", "https://ex.org/g2"]
      assert Mapping.normalize(normalized) == normalized
    end

    test "normalize/1 on a bundle orders resources by mapping identity" do
      a = hand_resource()
      b = hand_resource(class_iris: ["https://ex.org/B"], ash_resource: "urn:test:B")

      %Bundle{resources: out} = Mapping.normalize(%Bundle{resources: [a, b]})
      %Bundle{resources: out_rev} = Mapping.normalize(%Bundle{resources: [b, a]})

      assert out == out_rev
      assert Enum.map(out, &Mapping.mapping_identity/1) == Enum.sort(Enum.map(out, &Mapping.mapping_identity/1))
    end

    test "validate/1 accepts a well-formed resource and bundle" do
      assert Mapping.validate(hand_resource()) == :ok
      assert Mapping.validate(%Bundle{resources: [hand_resource()]}) == :ok
    end

    test "validate/1 refuses missing identity proof" do
      assert {:error, [%Refusal{code: :REFUSED_NON_UNIQUE_SEMANTIC_IDENTITY}]} =
               Mapping.validate(hand_resource(identities: []))
    end

    test "validate/1 refuses invalid logical table and class iris" do
      assert {:error, refusals} =
               Mapping.validate(
                 hand_resource(
                   logical_table: %LogicalTable{table_name: "a", sql_query: "select 1"},
                   class_iris: ["not-absolute"]
                 )
               )

      codes = Enum.map(refusals, & &1.code)
      assert :REFUSED_INVALID_LOGICAL_TABLE in codes
      assert :REFUSED_INVALID_CLASS_IRI in codes

      assert {:error, [%Refusal{code: :REFUSED_INVALID_CLASS_IRI}]} = Mapping.validate(hand_resource(class_iris: []))
    end

    test "validate/1 refuses a template column absent from the mapping" do
      subject = %SubjectMap{strategy: :template, value: "https://ex.org/a/{ghost}"}

      assert {:error, refusals} = Mapping.validate(hand_resource(subject_map: subject))
      assert :REFUSED_MISSING_SUBJECT_MAP in Enum.map(refusals, & &1.code)
    end

    test "validate/1 refuses an invalid graph map" do
      bad = hand_resource(graph_maps: [%GraphMap{strategy: :constant, value: "relative"}])
      assert {:error, [%Refusal{code: :REFUSED_INVALID_GRAPH_MAP}]} = Mapping.validate(bad)
    end

    test "validate/1 on a bundle refuses a reference to an unmapped parent" do
      ref = %AshR2RML.Mapping.ReferenceObjectMap{
        relationship: :parent,
        predicate_iri: "https://ex.org/parent",
        parent_resource: "urn:test:Missing",
        joins: [%JoinCondition{child: "parent_id", parent: "id"}]
      }

      bundle = %Bundle{resources: [hand_resource(reference_object_maps: [ref])]}
      assert {:error, [%Refusal{code: :REFUSED_RELATIONSHIP_TARGET_UNMAPPED}]} = Mapping.validate(bundle)
    end

    test "subject_identity_columns/1 per strategy" do
      assert Mapping.subject_identity_columns(hand_resource()) == ["id"]

      multi = hand_resource(subject_map: %SubjectMap{strategy: :template, value: "https://ex.org/{b}/{a}/{b}"})
      assert Mapping.subject_identity_columns(multi) == ["a", "b"]

      column = hand_resource(subject_map: %SubjectMap{strategy: :column, value: "uri"})
      assert Mapping.subject_identity_columns(column) == ["uri"]

      constant = hand_resource(subject_map: %SubjectMap{strategy: :constant, value: "https://ex.org/x"})
      assert Mapping.subject_identity_columns(constant) == []
      assert Mapping.subject_identity_columns(:other) == []
    end

    test "stable_subject_identity?/1 per subject strategy" do
      assert Mapping.stable_subject_identity?(hand_resource())
      refute Mapping.stable_subject_identity?(hand_resource(identities: [[:other]]))

      constant_ok = hand_resource(subject_map: %SubjectMap{strategy: :constant, value: "https://ex.org/x"})
      assert Mapping.stable_subject_identity?(constant_ok)

      constant_bad = hand_resource(subject_map: %SubjectMap{strategy: :constant, value: "relative"})
      refute Mapping.stable_subject_identity?(constant_bad)

      blank = hand_resource(subject_map: %SubjectMap{strategy: :template, value: "x", term_type: :blank_node})
      assert Mapping.stable_subject_identity?(blank)

      column = hand_resource(subject_map: %SubjectMap{strategy: :column, value: "id"})
      assert Mapping.stable_subject_identity?(column)
    end
  end

  describe "Introspection" do
    test "stable_subject_identity?/2 matches template fields against identities" do
      assert Introspection.stable_subject_identity?(Person, ["id"])
      refute Introspection.stable_subject_identity?(Person, ["name"])
      refute Introspection.stable_subject_identity?(Person, ["id", "name"])
      refute Introspection.stable_subject_identity?(Person, ["no_such_column"])
    end

    test "many_to_many_metadata/2 resolves bridge columns" do
      relationship = %{
        name: :shipments,
        type: :many_to_many,
        destination: Organization,
        through: Shipment,
        source_attribute: :id,
        destination_attribute: :id,
        source_attribute_on_join_resource: :region,
        destination_attribute_on_join_resource: :warehouse_code
      }

      assert {:ok, meta} = Introspection.many_to_many_metadata(Person, relationship)
      assert meta.kind == :many_to_many
      assert meta.cardinality == :many
      assert meta.source == Person
      assert meta.destination == Organization
      assert meta.through == Shipment
      assert meta.through_logical_table == %LogicalTable{table_name: to_string(Shipment)}
      assert meta.source_parent_column == "id"
      assert meta.source_join_column == "region"
      assert meta.destination_join_column == "warehouse_code"
      assert meta.destination_parent_column == "id"
      assert meta.source_to_join == %JoinCondition{child: "id", parent: "region"}
      assert meta.join_to_destination == %JoinCondition{child: "warehouse_code", parent: "id"}
      assert meta.joins == []
    end

    test "many_to_many_metadata/2 refuses missing join-resource metadata" do
      relationship = %{name: :broken, type: :many_to_many, destination: Organization, source_attribute: :id}

      assert {:error, %Refusal{code: :REFUSED_AMBIGUOUS_RELATIONSHIP, subject: {Person, :broken}}} =
               Introspection.many_to_many_metadata(Person, relationship)
    end
  end

  describe "DataLayer.infer_join_columns/2" do
    test "uses source/destination attributes" do
      assert DataLayer.infer_join_columns(Person, %{source_attribute: :organization_id, destination_attribute: :id}) ==
               {"organization_id", "id"}
    end

    test "falls back to join-resource attributes then :id" do
      assert DataLayer.infer_join_columns(Person, %{
               source_attribute_on_join_resource: :person_id,
               destination_attribute_on_join_resource: :org_id
             }) == {"person_id", "org_id"}

      assert DataLayer.infer_join_columns(Person, %{}) == {"id", "id"}
    end

    test "works against a real Ash relationship struct" do
      rel = Ash.Resource.Info.relationship(Person, :organization)
      assert DataLayer.infer_join_columns(Person, rel) == {"organization_id", "id"}
    end
  end

  describe "Resource.LegacyAdapter.convert/1" do
    test "converts a DSL-declared resource into a normalized mapping" do
      assert {:ok, %Resource{} = mapping} = AshR2RML.Resource.LegacyAdapter.convert(Person)

      assert mapping.ash_resource == Person
      assert mapping.class_iris == ["https://schema.org/Person"]
      assert mapping.logical_table == %LogicalTable{table_name: "schema_people"}
      assert mapping.subject_map.strategy == :template
      assert mapping.subject_map.value == "https://schema.org/Person/{id}"
      assert mapping.metadata.source == :compatibility

      assert Enum.map(mapping.predicate_object_maps, & &1.predicate_iri) ==
               ["https://schema.org/email", "https://schema.org/name"]

      assert [%{relationship: :organization, predicate_iri: "https://schema.org/memberOf"} = ref] =
               mapping.reference_object_maps

      assert ref.parent_resource == Organization
      assert ref.joins == [%JoinCondition{child: "organization_id", parent: "id"}]
      assert Mapping.validate(mapping) == :ok
    end

    test "refuses resources with no mapping" do
      assert {:error, %Refusal{code: :REFUSED_MISSING_SUBJECT_MAP, subject: Warehouse}} =
               AshR2RML.Resource.LegacyAdapter.convert(Warehouse)

      assert {:error, %Refusal{code: :REFUSED_MISSING_SUBJECT_MAP}} = AshR2RML.Resource.LegacyAdapter.convert(String)
    end
  end

  describe "Mix.Tasks.AshR2rml.GenerateDocs" do
    @describetag :tmp_dir

    test "writes the DSL cheat sheet relative to the working directory", %{tmp_dir: tmp_dir} do
      original = File.cwd!()
      on_exit(fn -> File.cd!(original) end)
      File.cd!(tmp_dir)

      capture_io(fn -> Mix.Tasks.AshR2rml.GenerateDocs.run([]) end)

      target = Path.join(tmp_dir, "documentation/reference/dsl_cheatsheet.md")
      assert File.regular?(target)
      assert File.read!(target) == AshR2RML.CheatSheet.generate()
      assert File.read!(target) =~ "r2rml"

      File.cd!(original)
      File.rm_rf!(Path.join(tmp_dir, "documentation"))
      refute File.exists?(target)
    end
  end
end
