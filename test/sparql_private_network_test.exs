# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.SPARQLPrivateNetworkTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Refusal
  alias AshR2RML.SPARQL.Protocol

  @q "SELECT * WHERE { ?s ?p ?o }"

  for host <- ~w(localhost 127.0.0.1 10.0.0.5 192.168.1.1 172.16.0.9 169.254.169.254 0.0.0.0) do
    test "refuses private host #{host} by default" do
      assert {:error, %Refusal{code: :REFUSED_INVALID_FEDERATION_ENVIRONMENT, evidence: %{private_network: true}}} =
               Protocol.query("http://#{unquote(host)}/sparql", @q)
    end
  end

  test "refuses IPv6 loopback and link-local" do
    for host <- ["[::1]", "[fe80::1]", "[fc00::1]"] do
      assert {:error, %Refusal{code: :REFUSED_INVALID_FEDERATION_ENVIRONMENT}} =
               Protocol.query("http://#{host}/sparql", @q)
    end
  end

  test "refuses IPv4-mapped IPv6 loopback and metadata, and IPv6 unspecified" do
    for host <- ["[::ffff:127.0.0.1]", "[::ffff:169.254.169.254]", "[::ffff:10.0.0.1]", "[::]"] do
      assert {:error, %Refusal{evidence: %{private_network: true}}} =
               Protocol.query("http://#{host}/sparql", @q)
    end
  end

  test "refuses 172.16/12 boundaries, 10/8 and 192.168/16 edges" do
    for host <- ~w(172.31.255.255 10.255.255.255 192.168.255.255 100.64.0.1) do
      assert {:error, %Refusal{evidence: %{private_network: true}}} =
               Protocol.query("http://#{host}/sparql", @q)
    end
  end

  test "mixed-case localhost and *.localhost are refused" do
    for host <- ["LOCALHOST", "foo.localhost"] do
      assert {:error, %Refusal{evidence: %{private_network: true}}} =
               Protocol.query("http://#{host}:8080/sparql", @q)
    end
  end

  test "unresolvable host is refused fail-closed, not passed through" do
    assert {:error, %Refusal{code: :REFUSED_INVALID_FEDERATION_ENVIRONMENT, evidence: %{dns_unresolved: true}}} =
             Protocol.query("http://no-such-host.invalid/sparql", @q, timeout: 1_000)
  end

  test "allow_private_network: true lifts the guard (connection then fails, not the guard)" do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, ip: {127, 0, 0, 1}])
    {:ok, port} = :inet.port(listen)
    :gen_tcp.close(listen)

    result = Protocol.query("http://127.0.0.1:#{port}/sparql", @q, allow_private_network: true, timeout: 1_000)
    refute match?({:error, %Refusal{evidence: %{private_network: true}}}, result)
  end
end
