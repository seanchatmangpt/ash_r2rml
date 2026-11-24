# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.SPARQLResultParityTest do
  use ExUnit.Case, async: true

  alias AshR2RML.{Parity, Refusal}
  alias AshR2RML.SPARQL.{Local, Protocol, Result}

  @p "https://example.org/p"
  @q "urn:q"

  defp graph do
    RDF.Graph.new([
      {RDF.iri("https://example.org/a"), RDF.iri(@p), RDF.literal("one")},
      {RDF.iri("https://example.org/b"), RDF.iri(@p), RDF.literal("two")}
    ])
  end

  # Real one-shot HTTP listener over :gen_tcp. Returns {url, pid}; serves one request.
  defp serve_once(status_line, body) do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])
    {:ok, port} = :inet.port(listen)

    spawn_link(fn ->
      {:ok, sock} = :gen_tcp.accept(listen, 10_000)
      read_request(sock, "")

      resp =
        "HTTP/1.1 #{status_line}\r\ncontent-type: application/sparql-results+json\r\n" <>
          "content-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n#{body}"

      :ok = :gen_tcp.send(sock, resp)
      :gen_tcp.shutdown(sock, :write)
      _ = :gen_tcp.recv(sock, 0, 2_000)
      :gen_tcp.close(sock)
      :gen_tcp.close(listen)
    end)

    "http://127.0.0.1:#{port}/sparql"
  end

  defp read_request(sock, acc) do
    case String.split(acc, "\r\n\r\n", parts: 2) do
      [head, rest] ->
        len =
          case Regex.run(~r/content-length:\s*(\d+)/i, head) do
            [_, n] -> String.to_integer(n)
            _ -> 0
          end

        if byte_size(rest) >= len do
          :ok
        else
          {:ok, more} = :gen_tcp.recv(sock, 0, 5_000)
          read_request(sock, acc <> more)
        end

      _ ->
        {:ok, more} = :gen_tcp.recv(sock, 0, 5_000)
        read_request(sock, acc <> more)
    end
  end

  describe "Result.bound/3" do
    test "passes through at or under the bound, refuses over it, ignores non-ok" do
      ok = {:ok, :bindings, [%{"a" => 1}, %{"a" => 2}]}
      assert Result.bound(ok, :s, 2) == ok

      assert {:error, %Refusal{code: :REFUSED_RESOURCE_BOUND}} = Result.bound(ok, :s, 1)
      assert Result.bound({:error, :x}, :s, 1) == {:error, :x}
    end
  end

  describe "Result.normalize/1" do
    test "bindings, boolean, and rdf shapes" do
      select = %SPARQL.Query.Result{
        variables: ["x"],
        results: [%{"x" => RDF.literal(7), "?y" => RDF.iri("urn:y")}]
      }

      assert Result.normalize(select) == {:ok, :bindings, [%{"x" => 7, "y" => "urn:y"}]}

      assert Result.normalize(%SPARQL.Query.Result{results: false}) ==
               {:ok, :boolean, [%{"ask" => false}]}

      assert {:ok, :rdf, rows} = Result.normalize(graph())

      assert Enum.sort_by(rows, & &1["subject"]) == [
               %{"subject" => "https://example.org/a", "predicate" => @p, "object" => "one"},
               %{"subject" => "https://example.org/b", "predicate" => @p, "object" => "two"}
             ]
    end
  end

  describe "Result.hash_rows/1" do
    test "order-insensitive, sensitive to content and multiplicity" do
      r1 = %{"a" => 1}
      r2 = %{"a" => 2}

      assert Result.hash_rows([r1, r2]) == Result.hash_rows([r2, r1])
      assert Result.hash_rows([r1, r2]) != Result.hash_rows([r1, %{"a" => 3}])
      assert Result.hash_rows([r1, r1]) != Result.hash_rows([r1])
      assert Result.hash_rows([]) == Result.hash_rows([])
      assert Result.hash_rows([]) != Result.hash_rows([r1])
    end
  end

  describe "Parity.compare/5" do
    test "mismatch yields unverified receipt with differing hashes and counts" do
      receipt = Parity.compare(:sparql_sql, "s", [%{"a" => 1}], [%{"a" => 2}])

      refute receipt.verified?
      refute receipt.observed?
      assert receipt.left_result_sha256 != receipt.right_result_sha256
      assert {receipt.left_count, receipt.right_count} == {1, 1}
    end

    test "empty inputs verify with equal hashes" do
      receipt = Parity.compare(:sparql_sql, "s", [], [])
      assert receipt.verified?
      assert receipt.left_result_sha256 == receipt.right_result_sha256
      assert {receipt.left_count, receipt.right_count} == {0, 0}
    end

    test "duplicate rows are a multiset, not a set" do
      row = %{"a" => 1}
      receipt = Parity.compare(:sparql_sql, "s", [row, row], [row])
      refute receipt.verified?
      assert {receipt.left_count, receipt.right_count} == {2, 1}

      assert Parity.compare(:sparql_sql, "s", [row, row], [row, row]).verified?
    end
  end

  describe "Local.query/3" do
    test "ASK true and false" do
      assert {:ok, yes} = Local.query(graph(), "ASK { ?s <#{@p}> \"one\" }")
      assert yes.result_kind == :boolean
      assert yes.rows == [%{"ask" => true}]
      assert yes.query_form == :ask

      assert {:ok, no} = Local.query(graph(), "ASK { ?s <#{@p}> \"absent\" }")
      assert no.rows == [%{"ask" => false}]
      assert no.result_sha256 != yes.result_sha256
    end

    test "CONSTRUCT returns rdf rows" do
      q = "CONSTRUCT { ?s <#{@q}> ?o } WHERE { ?s <#{@p}> ?o }"
      assert {:ok, obs} = Local.query(graph(), q)
      assert obs.result_kind == :rdf
      assert obs.query_form == :construct

      assert Enum.sort_by(obs.rows, & &1["subject"]) == [
               %{"subject" => "https://example.org/a", "predicate" => @q, "object" => "one"},
               %{"subject" => "https://example.org/b", "predicate" => @q, "object" => "two"}
             ]

      assert obs.result_sha256 == Result.hash_rows(Enum.reverse(obs.rows))
    end
  end

  describe "Protocol.query/3 against a real local listener" do
    test "success path parses SPARQL JSON results" do
      body =
        ~s({"head":{"vars":["s","o"]},"results":{"bindings":[) <>
          ~s({"s":{"type":"uri","value":"http://example.org/a"},"o":{"type":"literal","value":"hi"}}]}})

      url = serve_once("200 OK", body)

      assert {:ok, obs} = Protocol.query(url, "SELECT ?s ?o WHERE { ?s ?p ?o }", timeout: 5_000)
      assert obs.strategy == :protocol
      assert obs.endpoint == url
      assert obs.result_kind == :bindings
      assert obs.rows == [%{"s" => "http://example.org/a", "o" => "hi"}]
      assert obs.result_sha256 == Result.hash_rows(obs.rows)
      assert obs.standing == :observed_remote_query
      assert obs.evidence_kind == :sparql_protocol
    end

    test "HTTP 500 is refused as an error" do
      url = serve_once("500 Internal Server Error", ~s({"error":"boom"}))
      assert {:error, _} = Protocol.query(url, "SELECT * WHERE { ?s ?p ?o }", timeout: 5_000)
    end
  end

  describe "Protocol.query_with/4" do
    test "uses the supplied client and labels standing test_double_only" do
      client = fn _parsed, _endpoint, _opts ->
        {:ok, %SPARQL.Query.Result{variables: ["x"], results: [%{"x" => RDF.literal(1)}]}}
      end

      assert {:ok, obs} =
               Protocol.query_with("http://example.org/sparql", "SELECT ?x WHERE { ?s ?p ?x }", [], client)

      assert obs.rows == [%{"x" => 1}]
      assert obs.standing == :test_double_only
      assert obs.evidence_kind == :injected_client
    end

    test "client error passes through and max_rows refuses" do
      failing = fn _, _, _ -> {:error, :boom} end
      q = "SELECT ?x WHERE { ?s ?p ?x }"
      assert Protocol.query_with("http://e.org/s", q, [], failing) == {:error, :boom}

      two = fn _, _, _ ->
        {:ok,
         %SPARQL.Query.Result{
           variables: ["x"],
           results: [%{"x" => RDF.literal(1)}, %{"x" => RDF.literal(2)}]
         }}
      end

      assert {:error, %Refusal{code: :REFUSED_RESOURCE_BOUND}} =
               Protocol.query_with("http://e.org/s", q, [max_rows: 1], two)
    end
  end
end
