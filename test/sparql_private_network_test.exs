# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Pins the SSRF guard: literal-IP/name vetting of private, loopback, link-local,
# CGNAT, documentation, benchmark, multicast, reserved, IPv4-compatible/mapped,
# NAT64, 6to4 and site-local ranges. No network access; literal hosts only.
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

  describe "private_ip?/1 range edges" do
    @private_v4 [
      {192, 0, 0, 0},
      {192, 0, 0, 255},
      {192, 0, 2, 0},
      {192, 0, 2, 255},
      {198, 18, 0, 0},
      {198, 19, 255, 255},
      {224, 0, 0, 0},
      {239, 255, 255, 255},
      {240, 0, 0, 0},
      {255, 255, 255, 255}
    ]
    @public_v4 [
      {192, 0, 1, 0},
      {192, 0, 3, 0},
      {198, 17, 255, 255},
      {198, 20, 0, 0},
      {223, 255, 255, 255},
      {8, 8, 8, 8}
    ]

    test "private IPv4 edges" do
      for ip <- @private_v4, do: assert(Protocol.private_ip?(ip), inspect(ip))
    end

    test "public IPv4 neighbours of the edges" do
      for ip <- @public_v4, do: refute(Protocol.private_ip?(ip), inspect(ip))
    end

    test "IPv4-compatible ::a.b.c.d follows the embedded v4" do
      assert Protocol.private_ip?({0, 0, 0, 0, 0, 0, 0x7F00, 1})
      assert Protocol.private_ip?({0, 0, 0, 0, 0, 0, 0x0A00, 1})
      refute Protocol.private_ip?({0, 0, 0, 0, 0, 0, 0x0808, 0x0808})
    end

    test "NAT64 64:ff9b::/96 follows the embedded v4" do
      assert Protocol.private_ip?({0x64, 0xFF9B, 0, 0, 0, 0, 0xA9FE, 0xA9FE})
      assert Protocol.private_ip?({0x64, 0xFF9B, 0, 0, 0, 0, 0x7F00, 1})
      refute Protocol.private_ip?({0x64, 0xFF9B, 0, 0, 0, 0, 0x0808, 0x0808})
    end

    test "6to4 2002::/16 follows the embedded v4" do
      assert Protocol.private_ip?({0x2002, 0x7F00, 1, 0, 0, 0, 0, 0})
      assert Protocol.private_ip?({0x2002, 0xC0A8, 0x0101, 1, 2, 3, 4, 5})
      refute Protocol.private_ip?({0x2002, 0x0808, 0x0808, 0, 0, 0, 0, 0})
    end

    test "fe80::/10 and fec0::/10 edges" do
      assert Protocol.private_ip?({0xFE80, 0, 0, 0, 0, 0, 0, 1})
      assert Protocol.private_ip?({0xFEBF, 0, 0, 0, 0, 0, 0, 1})
      assert Protocol.private_ip?({0xFEC0, 0, 0, 0, 0, 0, 0, 1})
      assert Protocol.private_ip?({0xFEFF, 0, 0, 0, 0, 0, 0, 1})
      refute Protocol.private_ip?({0x2606, 0x4700, 0, 0, 0, 0, 0, 1})
    end

    test "multicast, translated, NAT64 local-use, Teredo and documentation ranges" do
      assert Protocol.private_ip?({0xFF02, 0, 0, 0, 0, 0, 0, 1})
      assert Protocol.private_ip?({0xFF00, 0, 0, 0, 0, 0, 0, 0})
      assert Protocol.private_ip?({0, 0, 0, 0, 0xFFFF, 0, 0x7F00, 1})
      assert Protocol.private_ip?({0, 0, 0, 0, 0xFFFF, 0, 0x0A00, 1})
      refute Protocol.private_ip?({0, 0, 0, 0, 0xFFFF, 0, 0x0808, 0x0808})
      assert Protocol.private_ip?({0x64, 0xFF9B, 1, 0, 0, 0, 0x0808, 0x0808})
      assert Protocol.private_ip?({0x2001, 0, 1, 2, 3, 4, 5, 6})
      assert Protocol.private_ip?({0x2001, 0xDB8, 0, 0, 0, 0, 0, 1})
      refute Protocol.private_ip?({0x2001, 0x4860, 0, 0, 0, 0, 0, 1})
    end

    test "IPv4 documentation and 6to4-relay ranges" do
      for ip <- [{198, 51, 100, 0}, {198, 51, 100, 255}, {203, 0, 113, 7}, {192, 88, 99, 1}] do
        assert Protocol.private_ip?(ip), inspect(ip)
      end

      for ip <- [{198, 51, 101, 0}, {203, 0, 114, 0}, {192, 88, 100, 0}] do
        refute Protocol.private_ip?(ip), inspect(ip)
      end
    end

    test "trailing-dot localhost names are refused and userinfo never leaks on bad scheme" do
      for host <- ["localhost.", "foo.localhost."] do
        assert {:error, %Refusal{evidence: %{private_network: true}}} =
                 Protocol.query("http://#{host}/sparql", @q)
      end

      assert {:error, %Refusal{} = r} = Protocol.query("ftp://user:pw@93.184.216.34/x", @q)
      refute inspect(r) =~ "user:pw"
    end

    test "literal-IP endpoints in the new ranges are refused end to end" do
      for host <- [
            "192.0.0.1",
            "192.0.2.1",
            "198.18.0.1",
            "224.0.0.1",
            "240.0.0.1",
            "255.255.255.255",
            "[::7f00:1]",
            "[64:ff9b::7f00:1]",
            "[2002:7f00:1::]",
            "[fec0::1]"
          ] do
        assert {:error, %Refusal{evidence: %{private_network: true}}} =
                 Protocol.query("http://#{host}/sparql", @q)
      end
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
