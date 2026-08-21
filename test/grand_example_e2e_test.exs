# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GrandExampleE2ETest do
  use ExUnit.Case, async: true

  alias AshR2RML.GrandExample.Domain
  alias AshR2RML.GrandExample.Organization
  alias AshR2RML.GrandExample.Person
  alias AshR2RML.GrandExample.PublishingReactor
  alias AshR2RML.GrandExample.SemanticManifest
  alias AshR2RML.GrandExample.Types.SemVer
  alias AshR2RML.SPARQL.Observation

  defp build_observations do
    query_hash =
      :crypto.hash(:sha256, "SELECT ?s WHERE { ?s a <https://schema.org/Person> }")
      |> Base.encode16(case: :lower)

    rows = [%{"s" => "https://schema.org/Person/1"}]

    [
      %Observation{
        strategy: :direct_sparql,
        query_sha256: query_hash,
        query_form: :select,
        status: :ALIVE,
        standing: :observed,
        evidence_kind: :local_execution,
        rows: rows
      },
      %Observation{
        strategy: :r2rml_obda,
        query_sha256: query_hash,
        query_form: :select,
        status: :ALIVE,
        standing: :observed,
        evidence_kind: :local_execution,
        rows: rows
      }
    ]
  end

  describe "Grand Example: 100% Feature Utilization with Public Schema.org Ontologies" do
    test "custom SemVer type conforms to Ash.Type and AshR2RML.Type with standard XSD datatype" do
      assert AshR2RML.Datatype.Registry.supported?(SemVer)
      assert {:ok, dt} = AshR2RML.Datatype.Registry.resolve(SemVer)
      assert dt.rdf_datatype == "http://www.w3.org/2001/XMLSchema#string"
      assert SemVer.to_rdf_lexical("1.2.3") == "v1.2.3"
    end

    test "executes full PublishingReactor saga with compose, map, template, collect, prov-o, and differential" do
      inputs = %{
        resources: [Person, Organization, SemanticManifest],
        manifest_title: "Schema.org Public Enterprise Manifest",
        actor: %{id: "actor_admin", role: :admin},
        observations: build_observations(),
        metadata: %{ontology: "https://schema.org"}
      }

      assert {:ok, package} = Reactor.run(PublishingReactor, inputs)

      assert package.title == "Schema.org Public Enterprise Manifest"
      assert package.status == :ready_for_publication
      assert package.banner =~ "Semantic Manifest: Schema.org Public Enterprise Manifest"
      assert package.banner =~ "Validated 3 resource mappings"

      # Verify R2RML Turtle contains rendered public Schema.org classes, properties, and PROV-O provenance
      assert package.r2rml_turtle =~ "@prefix rr: <http://www.w3.org/ns/r2rml#>"
      assert package.r2rml_turtle =~ "rr:class <https://schema.org/Person>"
      assert package.r2rml_turtle =~ "rr:class <https://schema.org/Organization>"
      assert package.r2rml_turtle =~ "rr:class <https://schema.org/Dataset>"
      assert package.r2rml_turtle =~ "https://schema.org/name"
      assert package.r2rml_turtle =~ "https://schema.org/email"
      assert package.r2rml_turtle =~ "http://www.w3.org/ns/prov#generatedAtTime"
      assert package.r2rml_turtle =~ "http://www.w3.org/ns/prov#wasDerivedFrom"

      # Verify SPARQL behavioral differential completed
      assert package.differential_result.verified? == true
    end

    test "interacts with Ash SemanticManifest resource lifecycle and transactions" do
      # 1. Create manifest record via Ash action
      manifest =
        SemanticManifest
        |> Ash.Changeset.for_create(
          :create_manifest,
          %{
            title: "Public Release v1.0",
            status: :draft
          },
          domain: Domain
        )
        |> Ash.create!(domain: Domain)

      assert manifest.status == :draft

      # 2. Run the Grand Publishing Reactor
      inputs = %{
        resources: [Person, Organization],
        manifest_title: manifest.title,
        actor: nil,
        observations: [],
        metadata: %{}
      }

      assert {:ok, package} = Reactor.run(PublishingReactor, inputs)

      # 3. Update manifest record to published state with rendered Turtle
      updated_manifest =
        manifest
        |> Ash.Changeset.for_update(
          :mark_published,
          %{
            published_turtle: package.r2rml_turtle
          },
          domain: Domain
        )
        |> Ash.update!(domain: Domain)

      assert updated_manifest.status == :published
      assert updated_manifest.published_turtle =~ "rr:class <https://schema.org/Person>"

      # 4. Test revert status undo action
      reverted_manifest =
        updated_manifest
        |> Ash.Changeset.for_update(:revert_status, %{}, domain: Domain)
        |> Ash.update!(domain: Domain)

      assert reverted_manifest.status == :draft
    end
  end
end
