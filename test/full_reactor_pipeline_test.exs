# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.FullReactorPipelineTest.PipelineOrg do
  use Ash.Resource,
    domain: nil,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML]

  r2rml do
    class_iri("https://schema.org/Organization")
    subject_template("https://example.org/orgs/{id}")
    table_name("pipeline_orgs")

    attribute_mappings([
      {:name, "http://xmlns.com/foaf/0.1/name"}
    ])
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
  end
end

defmodule AshR2RML.FullReactorPipelineTest.PipelineUser do
  use Ash.Resource,
    domain: nil,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML]

  r2rml do
    class_iri("https://schema.org/Person")
    subject_template("https://example.org/users/{id}")
    table_name("pipeline_users")

    attribute_mappings([
      {:name, "http://xmlns.com/foaf/0.1/name"},
      {:email, "http://xmlns.com/foaf/0.1/mbox"}
    ])
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :email, :string, allow_nil?: false, public?: true
  end

  relationships do
    belongs_to :organization, AshR2RML.FullReactorPipelineTest.PipelineOrg do
      attribute_writable? true
    end
  end
end

defmodule AshR2RML.FullReactorPipelineTest do
  use ExUnit.Case, async: true

  alias AshR2RML.FullReactorPipelineTest.PipelineOrg
  alias AshR2RML.FullReactorPipelineTest.PipelineUser
  alias AshR2RML.Reactor.Pipeline
  alias AshR2RML.SPARQL.Observation

  defp build_observations do
    query_hash =
      :crypto.hash(:sha256, "SELECT ?s WHERE { ?s a <https://schema.org/Person> }")
      |> Base.encode16(case: :lower)

    rows = [%{"s" => "https://example.org/users/1"}]

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

  describe "AshR2RML.Reactor.Pipeline — full facet coverage" do
    test "pipeline compiles real Ash resources through all 7 steps and emits valid R2RML Turtle" do
      inputs = %{
        profile: [PipelineUser, PipelineOrg],
        actor: %{id: "actor_42", role: :admin},
        observations: build_observations(),
        metadata: %{workflow: "full_pipeline_test"}
      }

      assert {:ok, turtle} = Reactor.run(Pipeline, inputs)
      assert is_binary(turtle)
      assert turtle =~ "@prefix rr: <http://www.w3.org/ns/r2rml#>"
      assert turtle =~ "rr:class <https://schema.org/Person>"
    end

    test "pipeline attaches W3C PROV-O provenance predicate maps to rendered Turtle" do
      inputs = %{
        profile: [PipelineUser, PipelineOrg],
        actor: nil,
        observations: [],
        metadata: %{}
      }

      assert {:ok, turtle} = Reactor.run(Pipeline, inputs)
      assert turtle =~ "prov#generatedAtTime"
      assert turtle =~ "prov#wasDerivedFrom"
    end

    test "pipeline completes when actor is nil (no policy filtering applied)" do
      inputs = %{
        profile: [PipelineUser],
        actor: nil,
        observations: [],
        metadata: %{}
      }

      assert {:ok, turtle} = Reactor.run(Pipeline, inputs)
      assert is_binary(turtle)
    end
  end
end
