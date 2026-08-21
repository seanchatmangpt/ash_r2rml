# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Fortune5.GgenTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Fortune5.{DfCM, Ggen}

  defmodule Organization do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :name, :string, allow_nil?: false, public?: true
      attribute :country_code, :string, allow_nil?: false, public?: true
    end

    r2rml do
      table_name("organizations")
      class("https://www.w3.org/ns/org#Organization")

      subject do
        template("https://example.test/organization/{id}")
      end

      property(:name, "http://xmlns.com/foaf/0.1/name")
      property(:country_code, "https://example.test/ontology/countryCode")
    end
  end

  test "Fortune-5 manufacture emits semantic, DfCM, operations and real ggen pack surfaces" do
    graph = DfCM.default_graph()
    selection = DfCM.default_assignment(graph)

    assert {:ok, result} =
             AshR2RML.compile_fortune5(Organization,
               select: selection,
               max_candidates: 4,
               max_frontier: 4,
               max_examined: 4
             )

    assert result.status == :PARTIAL_ALIVE
    assert result.standing == :construct_only
    assert result.source == :ash
    assert result.dfcm.logical_cardinality == 1
    assert result.dfcm.enumeration_receipt.examined == 1
    assert length(result.dfcm.candidates) == 1
    assert length(result.dfcm.frontier) == 1
    assert result.capabilities.status == :PARTIAL_ALIVE
    assert result.production.status == :PARTIAL_ALIVE

    candidate = hd(result.dfcm.frontier)
    prefix = "generated/fortune5/candidates/#{candidate.id}"

    required = [
      "semantic/ontology.ttl",
      "semantic/shapes/operational-profile.ttl",
      "semantic/r2rml/mapping.ttl",
      "manufacturing/fortune5-pack/pack.toml",
      "manufacturing/fortune5-pack/ggen.toml",
      "manufacturing/fortune5-pack/fortune5/production-contract.ttl",
      "manufacturing/fortune5-pack/gates/010_semantic_subject.rq",
      "manufacturing/fortune5-pack/gates/040_authority_boundary.rq",
      "manufacturing/fortune5-pack/queries/candidates.rq",
      "manufacturing/fortune5-pack/templates/candidate_contract.json.tmpl",
      "generated/fortune5/dfcm/candidates.json",
      "generated/fortune5/dfcm/frontier.json",
      "generated/fortune5/capabilities/catalog.json",
      "generated/fortune5/capabilities/evidence-plan.json",
      "generated/fortune5/production/contract.json",
      "generated/fortune5/slo/objectives.json",
      "generated/fortune5/slo/capacity-scenarios.json",
      "generated/fortune5/routing/planning-cells.json",
      "generated/fortune5/operations/global-verification-plan.json",
      "generated/fortune5/operations/falsifier-catalog.md",
      "#{prefix}/candidate.json",
      "#{prefix}/observability.json",
      "#{prefix}/security.json",
      "#{prefix}/resilience.json",
      "#{prefix}/release.json",
      "#{prefix}/verification-plan.json",
      "#{prefix}/runtime.json",
      "#{prefix}/tenancy.json",
      "#{prefix}/data-governance.json",
      "#{prefix}/supply-chain.json",
      "#{prefix}/slo.json",
      "#{prefix}/routing.json",
      "#{prefix}/semantic-binding.json",
      "#{prefix}/runbook.md",
      "receipts/fortune5-manufacture.json"
    ]

    assert Enum.all?(required, &Map.has_key?(result.files, &1))
    assert map_size(result.files) >= length(required)
    assert result.receipt.generated_file_count == map_size(result.files)
    assert result.receipt.ggen_schema_ref == "7fc324df397973004059c37b752a365315d7bfb8"
    assert String.length(result.receipt.receipt_sha256) == 64
    assert String.length(result.receipt.projected_files_sha256) == 64
  end

  test "generated ggen manifest is strict and uses only current canonical generation modes" do
    pack = AshR2RML.fortune5_ggen_pack()
    manifest = pack["ggen.toml"]

    assert :ok = Ggen.validate_pack_source_files(pack)
    assert manifest =~ "strict_mode = true"
    assert manifest =~ "enable_llm = false"
    assert manifest =~ ~s(mode = "Overwrite")
    refute manifest =~ "CreateOrOverwrite"

    for query_path <- [
          "queries/candidates.rq",
          "queries/capabilities.rq",
          "queries/release_matrix.rq",
          "queries/authority_matrix.rq"
        ] do
      assert pack[query_path] =~ "ORDER BY"
    end
  end

  test "all generated JSON projections are syntactically valid" do
    graph = DfCM.default_graph()

    assert {:ok, result} =
             AshR2RML.compile_fortune5(Organization,
               select: DfCM.default_assignment(graph),
               max_candidates: 1,
               max_frontier: 1,
               max_examined: 1
             )

    json_files = Enum.filter(result.files, fn {path, _content} -> String.ends_with?(path, ".json") end)
    assert json_files != []

    for {path, content} <- json_files do
      assert {:ok, _decoded} = Jason.decode(content), "invalid generated JSON at #{path}"
    end
  end

  test "generated Fortune-5 RDF contract parses as Turtle" do
    graph = DfCM.default_graph()

    assert {:ok, result} =
             AshR2RML.compile_fortune5(Organization,
               select: DfCM.default_assignment(graph),
               max_candidates: 1,
               max_frontier: 1,
               max_examined: 1
             )

    ttl = result.files["manufacturing/fortune5-pack/fortune5/production-contract.ttl"]
    assert {:ok, rdf_graph} = RDF.Turtle.read_string(ttl)
    assert RDF.Graph.statement_count(rdf_graph) > 0
  end

  test "same admitted subject and exact DfCM selection manufacture byte-identical graph" do
    graph = DfCM.default_graph()
    opts = [select: DfCM.default_assignment(graph), max_candidates: 1, max_frontier: 1, max_examined: 1]

    assert {:ok, first} = AshR2RML.compile_fortune5(Organization, opts)
    assert {:ok, second} = AshR2RML.compile_fortune5(Organization, opts)

    assert first.files == second.files
    assert first.sha256 == second.sha256
    assert first.receipt == second.receipt
    assert first.dfcm.enumeration_receipt == second.dfcm.enumeration_receipt
  end

  test "staged hash verifier accepts exact graph and refuses drift" do
    graph = DfCM.default_graph()

    assert {:ok, result} =
             AshR2RML.compile_fortune5(Organization,
               select: DfCM.default_assignment(graph),
               max_candidates: 1,
               max_frontier: 1,
               max_examined: 1
             )

    assert {:ok, verified} = Ggen.verify_staged(result, result.sha256)
    assert verified.status == :ALIVE
    assert verified.standing == :ggen_staged_projection_hashes_verified

    [{path, _hash} | _] = Enum.to_list(result.sha256)
    drifted = Map.put(result.sha256, path, String.duplicate("0", 64))

    assert {:error, refusal} = Ggen.verify_staged(result, drifted)
    assert refusal.code == :REFUSED_GGEN_STAGED_HASH_MISMATCH
    assert refusal.evidence.mismatched != []
  end

  test "ggen pack preserves explicit no-ambient-DO authority fence" do
    pack = AshR2RML.fortune5_ggen_pack()
    gate = pack["gates/070_no_ambient_do.rq"]
    authority = pack["templates/authority_matrix.md.tmpl"]

    assert gate =~ "f5:ambientDo true"
    assert authority =~ "BRCE exclusive DO path"
    assert authority =~ "ambient DO authority"
  end
end
