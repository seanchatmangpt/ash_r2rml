# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Ggen.Production do
  @moduledoc """
  Construct dynamic input for the repository's `production/ggen` workspace.

  This module does not embed ggen gates, queries, templates, Kubernetes or other
  operational renderers in Elixir. Elixir constructs the admitted semantic and
  platform-neutral operational model; ggen owns final projection rendering and
  filesystem receipts.
  """

  alias AshR2RML.DfCM
  alias AshR2RML.Production
  alias AshR2RML.Production.{Capabilities, Deployment}

  @ns "https://w3id.org/ash-r2rml/production#"

  defmodule Receipt do
    @moduledoc "Identity of one dynamic ggen input graph."
    defstruct [
      :status,
      :standing,
      :semantic_subject_sha256,
      :design_space_sha256,
      :enumeration_receipt_sha256,
      :capability_receipt_sha256,
      :production_receipt_sha256,
      :input_ttl_sha256,
      :files_sha256,
      :receipt_sha256,
      :candidate_count
    ]
    @type t :: %__MODULE__{}
  end

  @spec compile(module() | [module()] | AshR2RML.Mapping.Bundle.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def compile(resources_or_bundle, opts \\ []) do
    profile = Keyword.get(opts, :profile, Production.default_profile())
    selection = Keyword.get(opts, :select, Production.default_assignment())
    evidence = Keyword.get(opts, :evidence, [])
    capability_observations = Keyword.get(opts, :capability_observations, [])
    requested_capabilities = Keyword.get(opts, :capabilities, profile.required_capabilities)

    with {:ok, semantic} <- AshR2RML.Ggen.TTL.emit(resources_or_bundle),
         {:ok, candidates, enumeration_receipt} <-
           DfCM.enumerate(profile.design_space,
             select: selection,
             max_candidates: Keyword.get(opts, :max_candidates, 128),
             max_examined: Keyword.get(opts, :max_examined, 10_000)
           ) do
      semantic_subject_sha256 = semantic_subject_sha256(semantic)
      production_admission = Production.admit(profile, semantic_subject_sha256, evidence)
      capability_admission = Capabilities.admit(requested_capabilities, capability_observations)
      frontier = DfCM.frontier(candidates)

      deployments =
        Enum.map(frontier, fn candidate ->
          Deployment.plan(candidate, semantic_subject_sha256,
            regions: Keyword.get(opts, :regions, ["us-west-2", "us-east-1"]),
            cells_per_region: Keyword.get(opts, :cells_per_region, 3)
          )
        end)

      input_ttl =
        render_input_ttl(
          semantic_subject_sha256,
          semantic,
          frontier,
          capability_admission,
          production_admission
        )

      base_files = %{
        "production/ggen/input.ttl" => input_ttl,
        "production/ggen/input/candidates.json" => canonical_json(Enum.map(frontier, &candidate_json/1)),
        "production/ggen/input/capabilities.json" => canonical_json(capability_admission),
        "production/ggen/input/admission.json" => canonical_json(production_admission),
        "production/ggen/input/deployments.json" => canonical_json(deployments),
        "production/ggen/input/semantic-hashes.json" => canonical_json(semantic.sha256)
      }

      hashes = file_hashes(base_files)

      base_receipt = %Receipt{
        status: :PARTIAL_ALIVE,
        standing: :construct_only_ggen_input,
        semantic_subject_sha256: semantic_subject_sha256,
        design_space_sha256: DfCM.space_sha256(profile.design_space),
        enumeration_receipt_sha256: enumeration_receipt.receipt_sha256,
        capability_receipt_sha256: capability_admission.receipt_sha256,
        production_receipt_sha256: production_admission.receipt_sha256,
        input_ttl_sha256: sha256_binary(input_ttl),
        files_sha256: DfCM.sha256(hashes),
        candidate_count: length(frontier),
        receipt_sha256: nil
      }

      receipt = %{base_receipt | receipt_sha256: DfCM.sha256(Map.from_struct(base_receipt))}
      files = Map.put(base_files, "production/ggen/input/receipt.json", canonical_json(receipt))

      {:ok,
       %{
         status: :PARTIAL_ALIVE,
         standing: :construct_only,
         source: :ash,
         semantic: semantic,
         candidates: frontier,
         deployments: deployments,
         capabilities: capability_admission,
         production: production_admission,
         enumeration_receipt: enumeration_receipt,
         receipt: receipt,
         files: files,
         sha256: file_hashes(files),
         workspace: "production/ggen/ggen.toml"
       }}
    end
  end

  @spec verify_staged(map(), map()) :: {:ok, map()} | {:error, map()}
  def verify_staged(%{files: files}, observed_hashes) when is_map(observed_hashes) do
    expected = file_hashes(files)

    observed =
      Map.new(observed_hashes, fn {path, hash} ->
        {to_string(path), String.downcase(to_string(hash))}
      end)

    missing = Map.keys(expected) -- Map.keys(observed)
    extra = Map.keys(observed) -- Map.keys(expected)

    mismatched =
      for {path, expected_hash} <- expected,
          Map.has_key?(observed, path),
          observed[path] != expected_hash do
        %{path: path, expected: expected_hash, observed: observed[path]}
      end

    if missing == [] and extra == [] and mismatched == [] do
      {:ok,
       %{
         status: :ALIVE,
         standing: :staged_input_hashes_verified,
         files_sha256: DfCM.sha256(expected)
       }}
    else
      {:error,
       %{
         code: :REFUSED_GGEN_STAGED_HASH_MISMATCH,
         missing: Enum.sort(missing),
         extra: Enum.sort(extra),
         mismatched: Enum.sort_by(mismatched, & &1.path)
       }}
    end
  end

  @spec workspace_files() :: [String.t()]
  def workspace_files do
    [
      "production/ggen/ggen.toml",
      "production/ggen/vocabulary.ttl",
      "production/ggen/gates/010_semantic_subject.rq",
      "production/ggen/gates/020_no_ambient_do.rq",
      "production/ggen/gates/030_candidate_identity.rq",
      "production/ggen/gates/040_admission_receipt.rq",
      "production/ggen/gates/050_alive_requires_alive_capabilities.rq",
      "production/ggen/gates/060_candidate_projection_closure.rq",
      "production/ggen/queries/candidates.rq",
      "production/ggen/queries/capabilities.rq",
      "production/ggen/queries/operational-candidates.rq",
      "production/ggen/queries/production-admission.rq",
      "production/ggen/templates/candidate-contract.md.tmpl",
      "production/ggen/templates/capability-matrix.md.tmpl",
      "production/ggen/templates/kubernetes-candidate.yaml.tmpl",
      "production/ggen/templates/release-plan.md.tmpl",
      "production/ggen/templates/otel-contract.yaml.tmpl",
      "production/ggen/templates/brce-authority.rego.tmpl",
      "production/ggen/templates/evidence-standing.md.tmpl"
    ]
  end

  defp render_input_ttl(subject_sha256, semantic, candidates, capability_admission, production_admission) do
    header = """
    @prefix p: <#{@ns}> .
    @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

    p:SemanticSubject a p:AdmittedSemanticSubject ;
      p:sha256 "#{subject_sha256}" ;
      p:constructOnly true .

    p:AuthorityBoundary a p:AuthorityContract ;
      p:ambientDo false ;
      p:brceOnlyDo true .

    p:ProductionAdmission a p:EvidenceAdmission ;
      p:status "#{production_admission.status}" ;
      p:receiptSha256 "#{production_admission.receipt_sha256}" .

    p:SemanticProjection a p:ProjectionSet ;
      p:ontologySha256 "#{semantic.sha256.ontology}" ;
      p:shaclSha256 "#{semantic.sha256.shacl}" ;
      p:r2rmlSha256 "#{semantic.sha256.r2rml}" .

    """

    candidate_ttl =
      candidates
      |> Enum.sort_by(& &1.id)
      |> Enum.map(&render_candidate/1)
      |> Enum.join("\n")

    capability_ttl =
      capability_admission.closure
      |> Enum.sort()
      |> Enum.map(fn capability ->
        status = capability_status(capability_admission, capability)

        """
        <#{@ns}capability/#{capability}> a p:CapabilityStanding ;
          p:capabilityId "#{capability}" ;
          p:status "#{status}" .
        """
      end)
      |> Enum.join("\n")

    header <> candidate_ttl <> capability_ttl
  end

  defp render_candidate(candidate) do
    assignments =
      candidate.assignment
      |> Enum.sort_by(fn {key, _value} -> key end)
      |> Enum.map(fn {key, value} -> "  p:dim_#{key} \"#{escape(value)}\"" end)
      |> Enum.join(" ;\n")

    """
    <#{@ns}candidate/#{candidate.id}> a p:DesignCandidate ;
      p:candidateSha256 "#{candidate.id}" ;
    #{assignments} .
    """
  end

  defp candidate_json(candidate) do
    %{id: candidate.id, assignment: candidate.assignment, advisory: candidate.advisory}
  end

  defp capability_status(admission, capability) do
    cond do
      capability in admission.alive -> :ALIVE
      capability in admission.partial_alive -> :PARTIAL_ALIVE
      capability in admission.unknown -> :UNKNOWN
      true -> :UNSUPPORTED
    end
  end

  defp semantic_subject_sha256(semantic) do
    DfCM.sha256(%{source: semantic.source, sha256: semantic.sha256})
  end

  defp file_hashes(files) do
    Map.new(files, fn {path, content} -> {path, sha256_binary(content)} end)
  end

  defp sha256_binary(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)

  defp escape(value) do
    value
    |> to_string()
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
  end

  defp canonical_json(%_{} = struct), do: struct |> Map.from_struct() |> canonical_json()

  defp canonical_json(value) when is_map(value) do
    entries =
      value
      |> Enum.map(fn {key, item} -> {to_string(key), item} end)
      |> Enum.sort_by(&elem(&1, 0))

    "{" <>
      Enum.map_join(entries, ",", fn {key, item} ->
        Jason.encode!(key) <> ":" <> canonical_json(item)
      end) <> "}"
  end

  defp canonical_json(value) when is_list(value) do
    "[" <> Enum.map_join(value, ",", &canonical_json/1) <> "]"
  end

  defp canonical_json(value) when is_atom(value) and value in [true, false, nil], do: Jason.encode!(value)
  defp canonical_json(value) when is_atom(value), do: Jason.encode!(Atom.to_string(value))
  defp canonical_json(value), do: Jason.encode!(value)
end
