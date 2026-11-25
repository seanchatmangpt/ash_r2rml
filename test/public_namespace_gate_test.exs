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
                          test/sparql_result_parity_test.exs test/refusal_codes_coverage_test.exs
                          test/refactor_w9_guard_tests_test.exs)

  # Exact hosts only: loopback, the documentation ranges (RFC 5737), the example.com address,
  # a host under the reserved .invalid TLD, or an interpolated / empty host. A host must end at
  # its port or path, so `localhost.evil.test` or `127.0.0.1.evil.test` is not exempt.
  @endpoint_host ~r/^https?:\/\/(?:[^@\/]*@)?(?:(?:127\.0\.0\.1|93\.184\.216\.34|(?:192\.0\.2|198\.51\.100|203\.0\.113)\.\d{1,3}|localhost|\[::1\]|(?:[a-z0-9-]+\.)*[a-z0-9-]+\.invalid)(?::(?:\d+|[#]\{[^}]*\}))?(?:[\/?#\\]|$)|[#]\{|\{|\/|$)/i

  defp endpoint_exception?(relative_file, iri) do
    relative_file in @endpoint_test_files and Regex.match?(@endpoint_host, iri)
  end

  # Scheme names are case-insensitive (RFC 3986 section 3.1): an uppercase scheme is extracted
  # and then classified by its lowercased scheme, so it cannot hide from the scan.
  @iri_pattern ~r{(?:https?://|(?<![A-Za-z0-9_])urn:)[^\s"'`<>()\[\]\\,;|]+}i

  # Only http, https and urn are admissible schemes. Any other IRI scheme is non-public. Listed
  # explicitly: file, ftp/ftps/sftp, ws/wss, s3, gs, ssh, git, ldap/ldaps, data, jdbc, mailto,
  # did and tag. Each alternative needs the shape of a
  # real IRI of that scheme, so keyword-style text such as `file: path` is not a hit.
  @foreign_scheme_pattern Regex.compile!(
                            ~S"""
                            (?<![A-Za-z0-9_])(?:(?:file|sftp|ftps?):/[^\s"'`<>()\[\]\\,;|]*|(?:wss?|s3|gs|ssh|git|ldaps?)://[^\s"'`<>()\[\]\\,;|]*|data:[a-z]+/[a-z0-9.+-]+[^\s"'`<>()\[\]\\,;|]*|jdbc:[a-z0-9]+:[^\s"'`<>()\[\]\\,;|]+|mailto:[^\s"'`<>()\[\]\\,;|@]*@[^\s"'`<>()\[\]\\,;|]*|did:[a-z0-9]+:[^\s"'`<>()\[\]\\,;|]+|tag:[a-z0-9.-]+,\d{4}[^\s"'`<>()\[\]\\;|]*)
                            """
                            |> String.trim(),
                            "i"
                          )

  # IRIs assembled from parts: a scheme-only string literal followed by the concatenation
  # operator, or a concatenation operator followed by a literal that starts with the authority
  # slashes. Both defeat the literal scan above.
  @concat_pattern ~r{["'](?:https?|ftp|file|urn|tag|did|mailto):(?://)?["']\s*<>|<>\s*["']:?//}i

  # IRIs assembled with Enum.join: a join whose first element is a scheme-only literal
  # (`"https:"`, `"https://"`, `"urn:"`) followed by more parts.
  @join_pattern ~r/Enum\.join\(\[\s*["'](?:https?|ftp|file|urn):(?:\/\/)?["']\s*,/i

  # IRIs assembled by interpolation: an interpolated scheme directly followed by `://` (or `//`)
  # and a dotted host-ish literal, e.g. scheme-var then `://host.test`.
  @interp_pattern ~r/#\{[^}]*\}:?\/\/[A-Za-z0-9-]+\.[A-Za-z]/

  # A line carrying this marker is a deliberate rule fixture and is exempt from the concat rule.
  # The marker is honoured in this gate file only (non-vacuity fixtures that must build IRIs
  # from parts to avoid tripping the very scan they exercise).
  @fixture_marker "CONCAT-GATE-FIXTURE"
  @gate_file "test/public_namespace_gate_test.exs"

  # Documented exceptions to the concat rule outside the gate file: {file, exact line text, reason}.
  # test/refactor_w6_strict_wiring_test.exs builds an off-list IRI with Enum.join on purpose: it
  # is the fixture proving that strict mode refuses an IRI outside the allowed prefixes.
  @concat_exceptions [
    {"test/refactor_w6_strict_wiring_test.exs", "Enum.join([\"https:\", \"\", @offlist_host,",
     "deliberate off-list IRI fixture for strict-mode refusal"}
  ]

  defp scanned_files, do: Path.wildcard(Path.join(@root, "{lib,test}/**/*.{ex,exs}"))

  # Lowercase the scheme only; the remainder of the IRI is compared exactly.
  defp normalize_scheme(iri) do
    case Regex.run(~r/^([A-Za-z][A-Za-z0-9+.-]*:)(.*)$/s, iri) do
      [_, scheme, rest] -> String.downcase(scheme) <> rest
      nil -> iri
    end
  end

  # A bare namespace without its trailing slash (e.g. `https://schema.org`) is the same namespace.
  defp admitted?(raw_iri) do
    iri = normalize_scheme(raw_iri)
    prefixes = @public_namespaces ++ Enum.map(@exceptions, &elem(&1, 0))

    Enum.any?(prefixes, &prefix_admits?(iri, &1))
  end

  # A namespace prefix (ending in `/`, `#` or `:`) admits everything beneath it. Any other entry
  # is a whole IRI and admits only itself, so `<iri>-suffix` is not smuggled in by prefix match.
  defp prefix_admits?(iri, prefix) do
    if String.ends_with?(prefix, ["/", "#", ":"]) do
      String.starts_with?(iri, prefix) or iri == String.trim_trailing(prefix, "/")
    else
      iri == prefix
    end
  end

  defp iris_in(line) do
    @iri_pattern |> Regex.scan(line) |> List.flatten() |> Enum.map(&String.trim_trailing(&1, "."))
  end

  defp foreign_schemes_in(line) do
    @foreign_scheme_pattern |> Regex.scan(line) |> List.flatten()
  end

  # Scheme-refusal tests in the endpoint files feed non-public schemes on purpose.
  defp foreign_scheme_exception?(relative_file), do: relative_file in @endpoint_test_files

  defp concat_hit?(relative_file, line) do
    (Regex.match?(@concat_pattern, line) or Regex.match?(@join_pattern, line) or
       Regex.match?(@interp_pattern, line)) and
      not (relative_file == @gate_file and String.contains?(line, @fixture_marker)) and
      not Enum.any?(@concat_exceptions, fn {file, text, _reason} ->
        file == relative_file and String.contains?(line, text)
      end)
  end

  defp source_lines do
    for file <- scanned_files(),
        {line, number} <- file |> File.read!() |> String.split("\n") |> Enum.with_index(1) do
      {Path.relative_to(file, @root), number, line}
    end
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
    refute admitted?(Enum.join(["https:", "//invented.test/thing"])), "CONCAT-GATE-FIXTURE"
    refute admitted?(Enum.join(["https:", "//schema.org.invented/"])), "CONCAT-GATE-FIXTURE"
    refute admitted?("ur" <> "n:invented:thing")
  end

  test "the contributors URL exception admits only that exact IRI (non-vacuity)" do
    {contributors, _reason} = Enum.at(@exceptions, 2)

    assert admitted?(contributors)
    refute admitted?(contributors <> "-evil")
    refute admitted?(contributors <> "/x")
    refute admitted?(contributors <> ".invented")
  end

  test "uppercase schemes are extracted and classified (non-vacuity)" do
    upper = "HT" <> "TPS://schema.org/name"
    assert iris_in(~s|x = "#{upper}"|) == [upper]
    assert admitted?(upper)
    refute admitted?("HT" <> "TPS://invented.test/x")
    refute admitted?("HT" <> "TP://schema.org.invented/x")
    assert iris_in("UR" <> "N:uuid:1") == ["UR" <> "N:uuid:1"]
    refute admitted?("UR" <> "N:invented:x")
  end

  test "non-http IRI schemes are detected (non-vacuity)" do
    samples = [
      "fi" <> "le:///etc/passwd",
      "FI" <> "LE:///etc/passwd",
      "ft" <> "p://h.test/x",
      "ftp" <> "s://h.test/x",
      "sft" <> "p://h.test/x",
      "mail" <> "to:a@b.test",
      "d" <> "id:web:h.test",
      "t" <> "ag:h.test,2026:x"
    ]

    for sample <- samples do
      assert foreign_schemes_in(~s|x = "#{sample}"|) != [], "#{sample} not detected"
    end

    # keyword-style text and ordinary words are not IRIs
    for clean <- ["file: path", "tag: x", "did: y", "ftp_host: z", "profile:/x", "mailto: nobody"] do
      assert foreign_schemes_in(clean) == [], "#{clean} wrongly detected"
    end

    refute foreign_scheme_exception?("lib/ash_r2rml/domain.ex")
    assert foreign_scheme_exception?("test/sparql_protocol_hardening_test.exs")
  end

  test "newly listed schemes are caught (non-vacuity)" do
    samples = [
      "w" <> "s://h.test/x",
      "w" <> "ss://h.test/x",
      "s" <> "3://bucket/key",
      "g" <> "s://bucket/key",
      "s" <> "sh://h.test/x",
      "g" <> "it://h.test/r.git",
      "ld" <> "ap://h.test/dc=x",
      "ld" <> "aps://h.test/dc=x",
      "da" <> "ta:text/plain;base64",
      "jd" <> "bc:postgresql://h.test/db",
      "WS" <> "S://h.test/x"
    ]

    for sample <- samples do
      assert foreign_schemes_in(~s|x = "#{sample}"|) != [], "#{sample} not detected"
    end

    for clean <- ["ws: 1", "git: x", "s3: y", "data: z", "gs_path: q", "jdbc: no"] do
      assert foreign_schemes_in(clean) == [], "#{clean} wrongly detected"
    end
  end

  test "the endpoint host exemption is exact and scoped to endpoint files (non-vacuity)" do
    endpoint_file = "test/sparql_protocol_hardening_test.exs"
    http = "ht" <> "tp://"

    for host <- [
          "127.0.0.1:8080/x",
          "localhost/x",
          "localhost:3000",
          "[::1]:1/x",
          "93.184.216.34/sparql",
          "203.0.113.7/x",
          "a.invalid/x",
          "/sparql",
          ""
        ] do
      assert endpoint_exception?(endpoint_file, http <> host), "#{host} not exempt"
    end

    for host <- [
          "localhost.evil.test/x",
          "localhost@evil.test/x",
          "127.0.0.1.evil.test/x",
          "evil.invalid.test/x",
          "evil.test/x",
          "localhostevil/x"
        ] do
      refute endpoint_exception?(endpoint_file, http <> host), "#{host} wrongly exempt"
    end

    refute endpoint_exception?("lib/ash_r2rml/domain.ex", http <> "127.0.0.1/x")
  end

  test "IRIs assembled from parts are detected (non-vacuity)" do
    scheme_literal = Enum.join(["a = ", ~s("https:"), " <> ", ~s("//h")])
    scheme_with_slashes = Enum.join([~s("https://"), " <> host"])
    slashes_literal = Enum.join([~s("a"), " <> ", ~s("//h")])
    split_colon = Enum.join([~s("http"), " <> ", ~s("://h")])

    for line <- [scheme_literal, scheme_with_slashes, slashes_literal, split_colon] do
      assert concat_hit?("lib/x.ex", line), "#{line} not detected"
    end

    refute concat_hit?("lib/x.ex", ~s|name = "a" <> "b"|)

    # the fixture marker is honoured in the gate file only
    marked = scheme_literal <> " # " <> @fixture_marker
    refute concat_hit?(@gate_file, marked)
    assert concat_hit?("lib/x.ex", marked)

    # the only documented exception is the strict-wiring off-list fixture, for that file alone
    assert [{"test/refactor_w6_strict_wiring_test.exs", _text, reason}] = @concat_exceptions
    assert String.length(reason) > 10
  end

  test "Enum.join and interpolation IRI assembly is detected (non-vacuity)" do
    # each fixture line is built from pieces so this file's own scan never sees the pattern
    join_line = Enum.join(["x = Enum.join([", ~s("https:"), ~s(, "", "h.test", "p"], "/")])
    join_slashes = Enum.join(["x = Enum.join([", ~s("urn:"), ~s(, "a"])])
    interp_line = Enum.join(["x = ", ~s("), "\#{scheme}", ~s(://h.test/p")])
    interp_slashes = Enum.join(["x = ", ~s("), "\#{s}", ~s(//h.test")])

    for line <- [join_line, join_slashes, interp_line, interp_slashes] do
      assert concat_hit?("lib/x.ex", line), "#{line} not detected"
    end

    # the named exception covers exactly the strict-wiring file and its off-list line
    strict = "test/refactor_w6_strict_wiring_test.exs"
    offlist = Enum.join(["c = Enum.join([", ~s("https:"), ~s(, "", @offlist_host, "ns"], "/")])
    refute concat_hit?(strict, offlist)
    assert concat_hit?("test/other_test.exs", offlist)
    assert concat_hit?(strict, join_line)

    # legitimate joins and interpolations are not hits
    refute concat_hit?("lib/x.ex", ~s|x = Enum.join(["a", "b"], "/")|)
    refute concat_hit?("lib/x.ex", ~s|x = "urn:uuid:\#{id}"|)
    refute concat_hit?("lib/x.ex", ~s|x = "\#{name}.test"|)
  end

  test "the gate sees the real source tree (non-vacuity)" do
    assert Enum.any?(scanned_files(), &String.ends_with?(&1, "lib/ash_r2rml/domain.ex"))
    assert Enum.any?(scanned_files(), &String.ends_with?(&1, "test/public_namespace_gate_test.exs"))
  end

  test "no non-public IRI scheme appears in lib/ or test/" do
    offenders =
      for {file, number, line} <- source_lines(),
          not foreign_scheme_exception?(file),
          hit <- foreign_schemes_in(line) do
        "#{file}:#{number}: #{hit}"
      end

    assert offenders == [],
           "only http, https and urn schemes are admissible; found:\n" <> Enum.join(offenders, "\n")
  end

  test "no IRI is assembled from parts in lib/ or test/" do
    offenders =
      for {file, number, line} <- source_lines(), concat_hit?(file, line) do
        "#{file}:#{number}: #{String.trim(line)}"
      end

    assert offenders == [],
           "write IRIs as whole literals so the namespace scan can see them:\n" <>
             Enum.join(offenders, "\n")
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
