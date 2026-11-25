# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.PublicNamespaceGateTest do
  @moduledoc """
  Source-scan gate: every IRI literal (http or https scheme, or a URN) in `lib/` and `test/`
  must start with a ratified public namespace. Invented, app-local or example-domain IRIs
  fail with file:line. This file is scanned too.
  """
  use ExUnit.Case, async: true

  @root Path.expand("..", __DIR__)

  # Ratified public namespaces (full namespace IRIs).
  @public_namespaces [
    # rdf
    "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
    # rdfs
    "http://www.w3.org/2000/01/rdf-schema#",
    # xsd
    "http://www.w3.org/2001/XMLSchema#",
    # owl
    "http://www.w3.org/2002/07/owl#",
    # sh
    "http://www.w3.org/ns/shacl#",
    # shui
    "http://www.w3.org/ns/shacl-ui#",
    # time
    "http://www.w3.org/2006/time#",
    # org
    "http://www.w3.org/ns/org#",
    # odrl
    "http://www.w3.org/ns/odrl/2/",
    # foaf
    "http://xmlns.com/foaf/0.1/",
    # skos
    "http://www.w3.org/2004/02/skos/core#",
    # prov
    "http://www.w3.org/ns/prov#",
    # p-plan
    "http://purl.org/net/p-plan#",
    # dcterms
    "http://purl.org/dc/terms/",
    # schema (both schemes in use)
    "https://schema.org/",
    "http://schema.org/",
    # fibo-fnd-acc-cur
    "https://spec.edmcouncil.org/fibo/ontology/FND/Accounting/CurrencyAmount/",
    # fibo-fbc-pas-caa
    "https://spec.edmcouncil.org/fibo/ontology/FBC/ProductsAndServices/ClientsAndAccounts/",
    # ocel
    "https://www.ocel-standard.org/",
    # identifier schemes
    "urn:uuid:",
    "urn:sha256:"
  ]

  # Exact documented exceptions: {prefix, reason}.
  @exceptions [
    {"http://www.w3.org/ns/r2rml#", "W3C R2RML vocabulary: the vocabulary this library renders"},
    {"http://www.opengis.net/ont/geosparql#", "OGC GeoSPARQL datatype namespace (public standard)"},
    {"https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors",
     "SPDX-FileCopyrightText header URL present in every source file"}
  ]

  # SPARQL protocol tests address network endpoints (loopback, documentation addresses, the
  # reserved .invalid TLD, interpolated hosts). An endpoint URL locates a service; it is not an
  # RDF term, so the namespace allowlist does not apply to it -- in these files only.
  @endpoint_test_files ~w(test/sparql_protocol_hardening_test.exs test/sparql_private_network_test.exs
                          test/sparql_result_parity_test.exs test/refusal_codes_coverage_test.exs)

  @endpoint_host ~r/^https?:\/\/(?:[^@\/]*@)?(?:\d{1,3}(?:\.\d{1,3}){3}|localhost|\[[0-9a-f:]+\]|[^\/]*\.invalid|[#]\{|\{|\/)/i

  defp endpoint_exception?(relative_file, iri) do
    relative_file in @endpoint_test_files and Regex.match?(@endpoint_host, iri)
  end

  @iri_pattern ~r{(?:https?://|(?<![A-Za-z0-9_])urn:)[^\s"'`<>()\[\]\\,;|]+}

  defp scanned_files, do: Path.wildcard(Path.join(@root, "{lib,test}/**/*.{ex,exs}"))

  # A bare namespace without its trailing slash (e.g. `https://schema.org`) is the same namespace.
  defp admitted?(iri) do
    prefixes = @public_namespaces ++ Enum.map(@exceptions, &elem(&1, 0))

    Enum.any?(prefixes, fn prefix ->
      String.starts_with?(iri, prefix) or iri == String.trim_trailing(prefix, "/")
    end)
  end

  defp iris_in(line) do
    @iri_pattern |> Regex.scan(line) |> List.flatten() |> Enum.map(&String.trim_trailing(&1, "."))
  end

  test "every exception carries a reason" do
    for {prefix, reason} <- @exceptions do
      assert is_binary(prefix) and String.length(reason) > 10
    end
  end

  test "the scanner extracts and classifies IRIs (non-vacuity)" do
    assert iris_in(~s|x = "https://schema.org/name"|) == ["https://schema.org/name"]
    assert iris_in(~s|x = "urn:uuid:{id}"|) == ["urn:uuid:{id}"]
    # `urn:` inside an identifier such as `return:` is not an IRI
    assert iris_in("return: value") == []

    assert admitted?("https://schema.org/name")
    assert admitted?("urn:uuid:{id}")
    assert admitted?("urn:sha256:00")
    # built from parts so this file's own scan does not see invented IRIs
    refute admitted?("https:" <> "//invented.test/thing")
    refute admitted?("https:" <> "//schema.org.invented/")
    refute admitted?("ur" <> "n:invented:thing")
  end

  test "the gate sees the real source tree (non-vacuity)" do
    assert Enum.any?(scanned_files(), &String.ends_with?(&1, "lib/ash_r2rml/domain.ex"))
    assert Enum.any?(scanned_files(), &String.ends_with?(&1, "test/public_namespace_gate_test.exs"))
  end

  test "every IRI literal in lib/ and test/ is in a ratified public namespace" do
    offenders =
      for file <- scanned_files(),
          {line, number} <- file |> File.read!() |> String.split("\n") |> Enum.with_index(1),
          iri <- iris_in(line),
          not admitted?(iri),
          not endpoint_exception?(Path.relative_to(file, @root), iri) do
        "#{Path.relative_to(file, @root)}:#{number}: #{iri}"
      end

    assert offenders == [], "non-public IRIs found:\n" <> Enum.join(offenders, "\n")
  end
end
