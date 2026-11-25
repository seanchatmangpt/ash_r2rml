# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Pins Protocol hardening: endpoint scheme/userinfo/fragment/query refusal, client
# option allowlist, redirects off by default (follow_redirects opt-in), timeout
# merged into request_opts, and Local max_rows bounds.
defmodule AshR2RML.SPARQLProtocolHardeningTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Refusal
  alias AshR2RML.SPARQL.{Local, Protocol}

  @query "SELECT * WHERE { ?s ?p ?o }"

  for endpoint <- [
        "file:///etc/passwd",
        "ftp://93.184.216.34/sparql",
        "gopher://93.184.216.34/",
        "http://",
        "https:///sparql",
        "not a url",
        ""
      ] do
    test "Protocol.query refuses endpoint #{inspect(endpoint)}" do
      assert {:error, %Refusal{code: :REFUSED_INVALID_FEDERATION_ENVIRONMENT}} =
               Protocol.query(unquote(endpoint), @query)
    end
  end

  for endpoint <- [
        "http://user:pass@93.184.216.34/sparql",
        "http://user@93.184.216.34/sparql",
        "http://93.184.216.34/sparql#frag",
        "http://93.184.216.34/sparql#",
        "http://93.184.216.34/sparql?token=secret",
        "http://93.184.216.34/sparql?"
      ] do
    test "Protocol.query refuses userinfo/fragment/query endpoint #{inspect(endpoint)}" do
      assert {:error, %Refusal{code: :REFUSED_INVALID_FEDERATION_ENVIRONMENT} = refusal} =
               Protocol.query(unquote(endpoint), @query)

      refute inspect(refusal) =~ "user:pass"
      refute inspect(refusal) =~ "secret"
    end
  end

  test "client_opts disables redirects by default and drops non-allowlisted options" do
    opts =
      Protocol.client_opts(
        logger: true,
        max_redirects: 9,
        headers: [{"x", "y"}],
        request_method: :post,
        protocol_version: "1.1"
      )

    assert opts[:max_redirects] == 0
    assert opts[:request_method] == :post
    assert opts[:protocol_version] == "1.1"
    refute Keyword.has_key?(opts, :logger)
    refute Keyword.has_key?(opts, :headers)
  end

  test "client_opts follow_redirects is the only redirect opt-in" do
    assert Protocol.client_opts(follow_redirects: 2)[:max_redirects] == 2
    assert Protocol.client_opts(follow_redirects: -1)[:max_redirects] == 0
    assert Protocol.client_opts(follow_redirects: :yes)[:max_redirects] == 0
  end

  test "client_opts merges timeout into caller request_opts instead of replacing" do
    opts =
      Protocol.client_opts(
        timeout: 1_234,
        request_opts: [adapter: [timeout: 1, autoredirect: true, insecure: true], extra: 1]
      )

    assert opts[:request_opts][:adapter][:timeout] == 1_234
    assert opts[:request_opts][:adapter][:connect_timeout] == 1_234
    assert opts[:request_opts][:adapter][:autoredirect] == false
    assert opts[:request_opts][:adapter][:insecure] == true
    assert opts[:request_opts][:extra] == 1
    assert Protocol.client_opts([])[:request_opts][:adapter][:timeout] == 30_000
  end

  # Real local HTTP listeners over :gen_tcp; each connection is handled in a
  # spawned process and reports to the test pid. No sleeps: all waits are
  # deadline-bounded receives or accept timeouts.
  defp listen do
    {:ok, l} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])
    {:ok, port} = :inet.port(l)
    {l, port}
  end

  defp serve(l, name, handler) do
    parent = self()

    pid =
      spawn_link(fn ->
        case :gen_tcp.accept(l, 5_000) do
          {:ok, sock} ->
            send(parent, {:conn, name})
            handler.(sock)
            :gen_tcp.close(sock)

          {:error, _} ->
            :ok
        end

        :gen_tcp.close(l)
        send(parent, {:done, name})
      end)

    on_exit(fn -> :gen_tcp.close(l) end)
    pid
  end

  defp read_head(sock, acc \\ "") do
    if String.contains?(acc, "\r\n\r\n") do
      acc
    else
      case :gen_tcp.recv(sock, 0, 2_000) do
        {:ok, d} -> read_head(sock, acc <> d)
        _ -> acc
      end
    end
  end

  defp respond(sock, status, extra, body) do
    _ = read_head(sock)

    :gen_tcp.send(
      sock,
      "HTTP/1.1 #{status}\r\n#{extra}content-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n#{body}"
    )

    :gen_tcp.shutdown(sock, :write)
    _ = :gen_tcp.recv(sock, 0, 1_000)
  end

  @json ~s({"head":{"vars":["s"]},"results":{"bindings":[{"s":{"type":"literal","value":"ok"}}]}})

  test "real server: canned 200 SPARQL JSON returns a normal result" do
    {l, port} = listen()

    serve(l, :a, fn sock ->
      respond(sock, "200 OK", "content-type: application/sparql-results+json\r\n", @json)
    end)

    assert {:ok, obs} =
             Protocol.query("http://127.0.0.1:#{port}/sparql", @query,
               allow_private_network: true,
               timeout: 5_000
             )

    assert obs.rows == [%{"s" => "ok"}]
  end

  test "real server: 302 to a second listener is not followed and refuses typed" do
    {l1, p1} = listen()
    {l2, p2} = listen()

    serve(l1, :first, fn sock ->
      respond(sock, "302 Found", "location: http://127.0.0.1:#{p2}/evil\r\n", "")
    end)

    serve(l2, :second, fn sock ->
      respond(sock, "200 OK", "content-type: application/sparql-results+json\r\n", @json)
    end)

    assert {:error, %Refusal{code: :REFUSED_INVALID_FEDERATION_ENVIRONMENT, detail: detail}} =
             Protocol.query("http://127.0.0.1:#{p1}/sparql", @query,
               allow_private_network: true,
               timeout: 5_000
             )

    assert detail =~ "redirects are not followed"
    assert_receive {:conn, :first}, 5_000
    # Close the second listener so its accept ends deterministically.
    :gen_tcp.close(l2)
    assert_receive {:done, :second}, 5_000
    refute_received {:conn, :second}
  end

  test "real server: stalled server hits the timeout with an error within a bound" do
    {l, port} = listen()

    serve(l, :stall, fn sock ->
      _ = read_head(sock)
      # Never respond; wait until the client gives up and closes.
      _ = :gen_tcp.recv(sock, 0, 5_000)
    end)

    started = System.monotonic_time(:millisecond)

    assert {:error, _} =
             Protocol.query("http://127.0.0.1:#{port}/sparql", @query,
               allow_private_network: true,
               timeout: 300
             )

    assert System.monotonic_time(:millisecond) - started < 4_000
  end

  defp graph(n) do
    Enum.reduce(1..n, RDF.Graph.new(), fn i, g ->
      RDF.Graph.add(
        g,
        {RDF.iri("urn:uuid:00000000-0000-0000-0000-#{String.pad_leading("#{i}", 12, "0")}"),
         RDF.iri("https://schema.org/value"), RDF.literal(i)}
      )
    end)
  end

  test "Local.query under :max_rows returns all rows" do
    assert {:ok, obs} = Local.query(graph(3), @query, max_rows: 10)
    assert length(obs.rows) == 3
  end

  test "Local.query over :max_rows refuses with REFUSED_RESOURCE_BOUND" do
    assert {:error, %Refusal{code: :REFUSED_RESOURCE_BOUND}} = Local.query(graph(3), @query, max_rows: 2)
  end
end
