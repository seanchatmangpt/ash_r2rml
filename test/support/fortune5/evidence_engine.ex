# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Fortune5.EvidenceEngine do
  @moduledoc """
  Fortune 5 Enterprise Semantic Evidence & Telemetry Engine.

  Generates standards-compliant RDF evidence and IEEE OCEL 2.0 process multigraphs:
  1. EARL 1.0 test assertions (`earl:Assertion`, `earl:TestResult`, `earl:passed`, `earl:failed`, `earl:cantTell`, etc.)
  2. SOSA observations with QUDT units (`sosa:Observation`, `qudt:QuantityValue`, `qudt:numericValue`, `qudt:unit`)
  3. PROV-O execution lineage (`prov:Entity`, `prov:Activity`, `prov:Agent`, `prov:wasDerivedFrom`, `prov:wasGeneratedBy`)
  4. DCAT 3 enterprise catalog records (`dcat:Catalog`, `dcat:Dataset`, `dcat:Distribution`, `dcat:DataService`)
  5. IEEE/W3C OCEL 2.0 dynamic multigraphs and validation against `AshR2RML.Telemetry.OCEL2`
  """

  alias AshR2RML.Telemetry.OCEL2

  # Standard Prefixes
  @earl_ns "http://www.w3.org/ns/earl#"
  @sosa_ns "http://www.w3.org/ns/sosa/"
  @qudt_ns "http://qudt.org/schema/qudt/"
  @unit_ns "http://qudt.org/vocab/unit/"
  @prov_ns "http://www.w3.org/ns/prov#"
  @dcat_ns "http://www.w3.org/ns/dcat#"
  @dcterms_ns "http://purl.org/dc/terms/"
  @spdx_ns "https://spdx.org/rdf/3.0.0/terms/"
  @dqv_ns "http://www.w3.org/ns/dqv#"
  @f5_ns "https://enterprise.fortune5.com/ontology/"
  @f5_evidence_ns "https://enterprise.fortune5.com/evidence/"

  # ---------------------------------------------------------------------------
  # 1. EARL 1.0 Test Assertion Generator
  # ---------------------------------------------------------------------------

  @doc """
  Builds a W3C EARL 1.0 test assertion graph and Turtle string.

  Admitted outcomes: `:passed`, `:failed`, `:cantTell`, `:inapplicable`, `:untested`.
  """
  @spec build_earl_assertion(keyword()) ::
          {:ok, %{graph: RDF.Graph.t(), turtle: String.t(), id: String.t(), outcome: atom()}} | {:error, term()}
  def build_earl_assertion(opts \\ []) do
    id_suffix = Keyword.get(opts, :id, "assertion-" <> random_id())
    assertion_iri = RDF.iri("#{@f5_evidence_ns}earl/#{id_suffix}")
    result_iri = RDF.iri("#{@f5_evidence_ns}earl/result/#{id_suffix}")

    asserted_by = Keyword.get(opts, :asserted_by, "#{@f5_ns}agent/fortune5-adversarial-verifier") |> RDF.iri()
    subject = Keyword.get(opts, :subject, "#{@f5_ns}system/ash-r2rml-core") |> RDF.iri()
    test_criterion = Keyword.get(opts, :test_criterion, "#{@f5_ns}test/conformance/operational-admission") |> RDF.iri()
    outcome_atom = Keyword.get(opts, :outcome, :passed)
    mode_atom = Keyword.get(opts, :mode, :automatic)
    info = Keyword.get(opts, :info, "Formal semantic verification assertion passed with 100% operational closure.")
    pointer = Keyword.get(opts, :pointer, "urn:sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    timestamp = Keyword.get(opts, :timestamp, DateTime.utc_now() |> DateTime.to_iso8601())

    outcome_iri =
      case outcome_atom do
        :passed -> RDF.iri("#{@earl_ns}passed")
        :failed -> RDF.iri("#{@earl_ns}failed")
        :cantTell -> RDF.iri("#{@earl_ns}cantTell")
        :cant_tell -> RDF.iri("#{@earl_ns}cantTell")
        :inapplicable -> RDF.iri("#{@earl_ns}inapplicable")
        :untested -> RDF.iri("#{@earl_ns}untested")
        other -> RDF.iri("#{@earl_ns}#{other}")
      end

    mode_iri =
      case mode_atom do
        :manual -> RDF.iri("#{@earl_ns}manual")
        _ -> RDF.iri("#{@earl_ns}automatic")
      end

    triples = [
      # Assertion node
      {assertion_iri, RDF.iri(RDF.NS.RDF.type()), RDF.iri("#{@earl_ns}Assertion")},
      {assertion_iri, RDF.iri("#{@earl_ns}assertedBy"), asserted_by},
      {assertion_iri, RDF.iri("#{@earl_ns}subject"), subject},
      {assertion_iri, RDF.iri("#{@earl_ns}test"), test_criterion},
      {assertion_iri, RDF.iri("#{@earl_ns}result"), result_iri},
      {assertion_iri, RDF.iri("#{@earl_ns}mode"), mode_iri},

      # TestResult node
      {result_iri, RDF.iri(RDF.NS.RDF.type()), RDF.iri("#{@earl_ns}TestResult")},
      {result_iri, RDF.iri("#{@earl_ns}outcome"), outcome_iri},
      {result_iri, RDF.iri("#{@earl_ns}info"), RDF.literal(info)},
      {result_iri, RDF.iri("#{@earl_ns}pointer"), RDF.literal(pointer)},
      {result_iri, RDF.iri("#{@dcterms_ns}date"), RDF.literal(timestamp, datatype: RDF.NS.XSD.dateTime())}
    ]

    graph = RDF.Graph.new(triples)

    case RDF.Turtle.write_string(graph, prefixes: standard_prefixes()) do
      {:ok, turtle} ->
        {:ok, %{graph: graph, turtle: turtle, id: to_string(assertion_iri), outcome: outcome_atom}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # 2. SOSA Observation + QUDT Unit Generator
  # ---------------------------------------------------------------------------

  @doc """
  Builds a W3C SOSA observation graph with QUDT quantities and units.
  """
  @spec build_sosa_observation(keyword()) ::
          {:ok, %{graph: RDF.Graph.t(), turtle: String.t(), id: String.t(), value: number(), unit: String.t()}}
          | {:error, term()}
  def build_sosa_observation(opts \\ []) do
    id_suffix = Keyword.get(opts, :id, "obs-" <> random_id())
    obs_iri = RDF.iri("#{@f5_evidence_ns}sosa/#{id_suffix}")
    result_val_iri = RDF.iri("#{@f5_evidence_ns}sosa/result/#{id_suffix}")

    observed_prop = Keyword.get(opts, :observed_property, "#{@f5_ns}P99Latency") |> RDF.iri()
    feature = Keyword.get(opts, :feature_of_interest, "#{@f5_ns}service/ash-query-router") |> RDF.iri()
    sensor = Keyword.get(opts, :sensor, "#{@f5_ns}sensor/telemetry-latency-probe-01") |> RDF.iri()
    numeric_value = Keyword.get(opts, :numeric_value, 24.85)
    unit_iri = Keyword.get(opts, :unit, "#{@unit_ns}MilliSEC") |> RDF.iri()
    timestamp = Keyword.get(opts, :result_time, DateTime.utc_now() |> DateTime.to_iso8601())

    triples = [
      # Observation node
      {obs_iri, RDF.iri(RDF.NS.RDF.type()), RDF.iri("#{@sosa_ns}Observation")},
      {obs_iri, RDF.iri("#{@sosa_ns}observedProperty"), observed_prop},
      {obs_iri, RDF.iri("#{@sosa_ns}hasFeatureOfInterest"), feature},
      {obs_iri, RDF.iri("#{@sosa_ns}madeBySensor"), sensor},
      {obs_iri, RDF.iri("#{@sosa_ns}resultTime"), RDF.literal(timestamp, datatype: RDF.NS.XSD.dateTime())},
      {obs_iri, RDF.iri("#{@sosa_ns}hasResult"), result_val_iri},

      # QUDT QuantityValue node
      {result_val_iri, RDF.iri(RDF.NS.RDF.type()), RDF.iri("#{@qudt_ns}QuantityValue")},
      {result_val_iri, RDF.iri("#{@qudt_ns}numericValue"), RDF.literal(numeric_value, datatype: RDF.NS.XSD.decimal())},
      {result_val_iri, RDF.iri("#{@qudt_ns}unit"), unit_iri}
    ]

    graph = RDF.Graph.new(triples)

    case RDF.Turtle.write_string(graph, prefixes: standard_prefixes()) do
      {:ok, turtle} ->
        {:ok, %{graph: graph, turtle: turtle, id: to_string(obs_iri), value: numeric_value, unit: to_string(unit_iri)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # 3. W3C PROV-O Execution Lineage Generator
  # ---------------------------------------------------------------------------

  @doc """
  Builds a W3C PROV-O execution lineage graph connecting Activities, Agents, and Entities.
  """
  @spec build_prov_lineage(keyword()) ::
          {:ok, %{graph: RDF.Graph.t(), turtle: String.t(), activity_id: String.t()}} | {:error, term()}
  def build_prov_lineage(opts \\ []) do
    id_suffix = Keyword.get(opts, :id, "act-" <> random_id())
    activity_iri = RDF.iri("#{@f5_evidence_ns}prov/activity/#{id_suffix}")
    agent_iri = Keyword.get(opts, :agent, "#{@f5_ns}agent/orchestrator-node-01") |> RDF.iri()
    input_entity_iri = Keyword.get(opts, :input_entity, "#{@f5_evidence_ns}prov/entity/input-#{id_suffix}") |> RDF.iri()

    output_entity_iri =
      Keyword.get(opts, :output_entity, "#{@f5_evidence_ns}prov/entity/output-#{id_suffix}") |> RDF.iri()

    checksum_iri = RDF.iri("#{@f5_evidence_ns}prov/checksum/#{id_suffix}")

    started_at =
      Keyword.get(opts, :started_at, DateTime.utc_now() |> DateTime.add(-10, :second) |> DateTime.to_iso8601())

    ended_at = Keyword.get(opts, :ended_at, DateTime.utc_now() |> DateTime.to_iso8601())
    sha256 = Keyword.get(opts, :sha256, "b801f9a1e0b57e4e13d5272a95c47895e638b958807e155bcbe452ab9f66551b")

    triples = [
      # Activity node
      {activity_iri, RDF.iri(RDF.NS.RDF.type()), RDF.iri("#{@prov_ns}Activity")},
      {activity_iri, RDF.iri("#{@prov_ns}startedAtTime"), RDF.literal(started_at, datatype: RDF.NS.XSD.dateTime())},
      {activity_iri, RDF.iri("#{@prov_ns}endedAtTime"), RDF.literal(ended_at, datatype: RDF.NS.XSD.dateTime())},
      {activity_iri, RDF.iri("#{@prov_ns}wasAssociatedWith"), agent_iri},
      {activity_iri, RDF.iri("#{@prov_ns}used"), input_entity_iri},
      {activity_iri, RDF.iri("#{@spdx_ns}checksum"), checksum_iri},

      # Agent node
      {agent_iri, RDF.iri(RDF.NS.RDF.type()), RDF.iri("#{@prov_ns}Agent")},
      {agent_iri, RDF.iri(RDF.NS.RDF.type()), RDF.iri("#{@prov_ns}SoftwareAgent")},

      # Input Entity
      {input_entity_iri, RDF.iri(RDF.NS.RDF.type()), RDF.iri("#{@prov_ns}Entity")},

      # Output Entity with derivation
      {output_entity_iri, RDF.iri(RDF.NS.RDF.type()), RDF.iri("#{@prov_ns}Entity")},
      {output_entity_iri, RDF.iri("#{@prov_ns}wasGeneratedBy"), activity_iri},
      {output_entity_iri, RDF.iri("#{@prov_ns}wasDerivedFrom"), input_entity_iri},

      # SPDX Checksum node
      {checksum_iri, RDF.iri(RDF.NS.RDF.type()), RDF.iri("#{@spdx_ns}Checksum")},
      {checksum_iri, RDF.iri("#{@spdx_ns}algorithm"), RDF.iri("#{@spdx_ns}checksumAlgorithm_sha256")},
      {checksum_iri, RDF.iri("#{@spdx_ns}checksumValue"), RDF.literal(sha256)}
    ]

    graph = RDF.Graph.new(triples)

    case RDF.Turtle.write_string(graph, prefixes: standard_prefixes()) do
      {:ok, turtle} ->
        {:ok, %{graph: graph, turtle: turtle, activity_id: to_string(activity_iri)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # 4. W3C DCAT 3 Catalog Records Generator
  # ---------------------------------------------------------------------------

  @doc """
  Builds a W3C DCAT 3 catalog record structure containing Catalog, Dataset, Distribution, and DataService.
  """
  @spec build_dcat_catalog(keyword()) ::
          {:ok, %{graph: RDF.Graph.t(), turtle: String.t(), catalog_id: String.t(), dataset_id: String.t()}}
          | {:error, term()}
  def build_dcat_catalog(opts \\ []) do
    id_suffix = Keyword.get(opts, :id, "cat-" <> random_id())
    catalog_iri = RDF.iri("#{@f5_evidence_ns}dcat/catalog/#{id_suffix}")
    dataset_iri = RDF.iri("#{@f5_evidence_ns}dcat/dataset/#{id_suffix}")
    dist_iri = RDF.iri("#{@f5_evidence_ns}dcat/distribution/#{id_suffix}")
    service_iri = RDF.iri("#{@f5_evidence_ns}dcat/service/#{id_suffix}")

    title = Keyword.get(opts, :title, "Fortune 5 Telemetry & Semantic Evidence Dataset")

    description =
      Keyword.get(opts, :description, "High-fidelity semantic telemetry, operational logs, and EARL test assertions.")

    issued = Keyword.get(opts, :issued, DateTime.utc_now() |> DateTime.to_iso8601())
    access_url = Keyword.get(opts, :access_url, "https://enterprise.fortune5.com/api/v1/telemetry") |> RDF.iri()

    download_url =
      Keyword.get(opts, :download_url, "https://enterprise.fortune5.com/export/evidence.ndjson") |> RDF.iri()

    byte_size = Keyword.get(opts, :byte_size, 10_485_760)

    triples = [
      # Catalog node
      {catalog_iri, RDF.iri(RDF.NS.RDF.type()), RDF.iri("#{@dcat_ns}Catalog")},
      {catalog_iri, RDF.iri("#{@dcterms_ns}title"), RDF.literal("Fortune 5 Enterprise Evidence Catalog")},
      {catalog_iri, RDF.iri("#{@dcat_ns}dataset"), dataset_iri},
      {catalog_iri, RDF.iri("#{@dcat_ns}service"), service_iri},

      # Dataset node
      {dataset_iri, RDF.iri(RDF.NS.RDF.type()), RDF.iri("#{@dcat_ns}Dataset")},
      {dataset_iri, RDF.iri("#{@dcterms_ns}title"), RDF.literal(title)},
      {dataset_iri, RDF.iri("#{@dcterms_ns}description"), RDF.literal(description)},
      {dataset_iri, RDF.iri("#{@dcterms_ns}issued"), RDF.literal(issued, datatype: RDF.NS.XSD.dateTime())},
      {dataset_iri, RDF.iri("#{@dcat_ns}distribution"), dist_iri},

      # Distribution node
      {dist_iri, RDF.iri(RDF.NS.RDF.type()), RDF.iri("#{@dcat_ns}Distribution")},
      {dist_iri, RDF.iri("#{@dcat_ns}accessURL"), access_url},
      {dist_iri, RDF.iri("#{@dcat_ns}downloadURL"), download_url},
      {dist_iri, RDF.iri("#{@dcat_ns}mediaType"), RDF.literal("application/x-ndjson")},
      {dist_iri, RDF.iri("#{@dcat_ns}byteSize"), RDF.literal(byte_size, datatype: RDF.NS.XSD.integer())},

      # DataService node
      {service_iri, RDF.iri(RDF.NS.RDF.type()), RDF.iri("#{@dcat_ns}DataService")},
      {service_iri, RDF.iri("#{@dcterms_ns}title"), RDF.literal("Fortune 5 Telemetry Streaming Service")},
      {service_iri, RDF.iri("#{@dcat_ns}endpointURL"), access_url},
      {service_iri, RDF.iri("#{@dcat_ns}servesDataset"), dataset_iri}
    ]

    graph = RDF.Graph.new(triples)

    case RDF.Turtle.write_string(graph, prefixes: standard_prefixes()) do
      {:ok, turtle} ->
        {:ok, %{graph: graph, turtle: turtle, catalog_id: to_string(catalog_iri), dataset_id: to_string(dataset_iri)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # 5. IEEE OCEL 2.0 Dynamic Multigraph Emission & Validation
  # ---------------------------------------------------------------------------

  @doc """
  Emits an IEEE OCEL 2.0 dynamic multigraph event stream, validates against `AshR2RML.Telemetry.OCEL2`,
  and performs deterministic state reconstruction.
  """
  @spec emit_ocel2_multigraph(keyword()) ::
          {:ok, %{events: list(map()), ndjson: String.t(), validation: map(), reconstruction: map()}} | {:error, term()}
  def emit_ocel2_multigraph(opts \\ []) do
    base_time = Keyword.get(opts, :base_time, ~U[2026-08-21 12:00:00.000000Z])
    step_id = Keyword.get(opts, :step_prefix, "step-" <> random_id())

    events = [
      %{
        "ocel:eid" => "#{step_id}-001",
        "ocel:activity" => "admission_check_started",
        "ocel:timestamp" => DateTime.to_iso8601(base_time),
        "ocel:lifecycle" => "start",
        "ocel:omap" => ["service:router-01", "actor:verifier-daemon", "policy:sla-rule-p99"],
        "ocel:vmap" => %{
          "engine" => "AshR2RML.Fortune5.EvidenceEngine",
          "region" => "us-east-1",
          "p99_threshold_ms" => 50.0,
          "status" => "evaluating"
        },
        "ocel:e2o" => [
          %{"ocel:oid" => "service:router-01", "ocel:qualifier" => "target"},
          %{"ocel:oid" => "actor:verifier-daemon", "ocel:qualifier" => "actor"},
          %{"ocel:oid" => "policy:sla-rule-p99", "ocel:qualifier" => "input"}
        ]
      },
      %{
        "ocel:eid" => "#{step_id}-002",
        "ocel:activity" => "latency_observation_recorded",
        "ocel:timestamp" => DateTime.add(base_time, 2, :second) |> DateTime.to_iso8601(),
        "ocel:lifecycle" => "start",
        "ocel:omap" => ["service:router-01", "probe:latency-sensor-1", "observation:obs-42"],
        "ocel:vmap" => %{
          "measured_latency_ms" => 24.85,
          "qudt_unit" => "http://qudt.org/vocab/unit/MilliSEC",
          "sample_count" => 15000,
          "status" => "recorded"
        },
        "ocel:e2o" => [
          %{"ocel:oid" => "service:router-01", "ocel:qualifier" => "target"},
          %{"ocel:oid" => "probe:latency-sensor-1", "ocel:qualifier" => "resource"},
          %{"ocel:oid" => "observation:obs-42", "ocel:qualifier" => "output"}
        ]
      },
      %{
        "ocel:eid" => "#{step_id}-003",
        "ocel:activity" => "earl_assertion_sealed",
        "ocel:timestamp" => DateTime.add(base_time, 5, :second) |> DateTime.to_iso8601(),
        "ocel:lifecycle" => "stop",
        "ocel:omap" => ["service:router-01", "actor:verifier-daemon", "assertion:earl-pass-01", "manifest:sbom-v1"],
        "ocel:vmap" => %{
          "earl_outcome" => "passed",
          "sha256" => "b801f9a1e0b57e4e13d5272a95c47895e638b958807e155bcbe452ab9f66551b",
          "operational_closure" => "100%",
          "status" => "sealed"
        },
        "ocel:e2o" => [
          %{"ocel:oid" => "service:router-01", "ocel:qualifier" => "target"},
          %{"ocel:oid" => "actor:verifier-daemon", "ocel:qualifier" => "actor"},
          %{"ocel:oid" => "assertion:earl-pass-01", "ocel:qualifier" => "output"},
          %{"ocel:oid" => "manifest:sbom-v1", "ocel:qualifier" => "context"}
        ]
      }
    ]

    ndjson = Enum.map_join(events, "\n", &Jason.encode!/1)

    with {:ok, validation} <- OCEL2.validate(events),
         {:ok, reconstruction} <- OCEL2.reconstruct_from_events(events) do
      {:ok,
       %{
         events: events,
         ndjson: ndjson,
         validation: validation,
         reconstruction: reconstruction
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # 6. Unified Complete Evidence Bundle
  # ---------------------------------------------------------------------------

  @doc """
  Constructs a unified, fully cross-linked Fortune 5 Evidence Bundle combining
  EARL, SOSA+QUDT, PROV-O, DCAT 3, and validated OCEL 2.0 event multigraphs.
  """
  @spec build_complete_evidence_bundle(keyword()) ::
          {:ok, %{rdf_graph: RDF.Graph.t(), rdf_turtle: String.t(), ocel2: map()}} | {:error, term()}
  def build_complete_evidence_bundle(opts \\ []) do
    with {:ok, earl} <- build_earl_assertion(opts),
         {:ok, sosa} <- build_sosa_observation(opts),
         {:ok, prov} <- build_prov_lineage(opts),
         {:ok, dcat} <- build_dcat_catalog(opts),
         {:ok, ocel2} <- emit_ocel2_multigraph(opts) do
      # Merge all RDF graphs into a unified enterprise evidence knowledge graph
      merged_graph =
        RDF.Graph.new()
        |> RDF.Graph.add(earl.graph)
        |> RDF.Graph.add(sosa.graph)
        |> RDF.Graph.add(prov.graph)
        |> RDF.Graph.add(dcat.graph)

      case RDF.Turtle.write_string(merged_graph, prefixes: standard_prefixes()) do
        {:ok, turtle} ->
          {:ok,
           %{
             rdf_graph: merged_graph,
             rdf_turtle: turtle,
             statement_count: RDF.Graph.statement_count(merged_graph),
             ocel2: ocel2
           }}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Helper Functions
  # ---------------------------------------------------------------------------

  def standard_prefixes do
    %{
      "rdf" => RDF.iri(RDF.NS.RDF.type()) |> to_string() |> String.replace("type", ""),
      "rdfs" => "http://www.w3.org/2000/01/rdf-schema#",
      "owl" => "http://www.w3.org/2002/07/owl#",
      "xsd" => "http://www.w3.org/2001/XMLSchema#",
      "earl" => @earl_ns,
      "sosa" => @sosa_ns,
      "qudt" => @qudt_ns,
      "unit" => @unit_ns,
      "prov" => @prov_ns,
      "dcat" => @dcat_ns,
      "dcterms" => @dcterms_ns,
      "spdx" => @spdx_ns,
      "dqv" => @dqv_ns,
      "f5" => @f5_ns,
      "f5ev" => @f5_evidence_ns
    }
  end

  defp random_id do
    :crypto.strong_rand_bytes(8) |> Base.hex_encode32(case: :lower, padding: false)
  end
end
