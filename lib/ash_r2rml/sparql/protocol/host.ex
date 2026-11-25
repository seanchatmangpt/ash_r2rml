# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.SPARQL.Protocol.Host do
  @moduledoc """
  Host vetting for SPARQL protocol endpoints (SSRF guard).

  Decides whether the host a client is about to contact resolves to a private,
  loopback, link-local, metadata or otherwise reserved address. Vetting is
  strictly fail-closed: a name that does not resolve is refused, and a name is
  refused when ANY resolved address is private.

      iex> AshR2RML.SPARQL.Protocol.Host.private_ip?({127, 0, 0, 1})
      true
      iex> AshR2RML.SPARQL.Protocol.Host.private_ip?({93, 184, 216, 34})
      false

  `vet/1` returns the vetted addresses so `AshR2RML.SPARQL.Protocol` can pin the
  outbound connection to one of them (no second resolution).
  """

  @dns_timeout_ms 2_000

  @doc """
  Vets `host` (bracketed IPv6 literals and a trailing dot are accepted).

  Returns `:ok` when every address is public, `{:private, addrs}` with the
  offending addresses, or `:unresolved` when no A or AAAA record resolved.
  """
  @spec vet_host(String.t()) :: :ok | {:private, [:inet.ip_address()]} | :unresolved
  def vet_host(host) do
    case vet(host) do
      {:ok, _addrs} -> :ok
      other -> other
    end
  end

  @doc """
  Like `vet_host/1`, but returns the vetted addresses (`{:ok, addrs}`) so the
  caller can pin transport to exactly the addresses that were vetted instead of
  resolving the hostname a second time.
  """
  @spec vet(String.t()) :: {:ok, [:inet.ip_address()]} | {:private, [:inet.ip_address()]} | :unresolved
  def vet(host) do
    h =
      host
      |> String.trim_leading("[")
      |> String.trim_trailing("]")
      |> String.downcase()
      |> String.trim_trailing(".")

    name = String.to_charlist(h)

    cond do
      h == "localhost" or String.ends_with?(h, ".localhost") ->
        {:private, [{127, 0, 0, 1}]}

      true ->
        case :inet.parse_address(name) do
          {:ok, ip} -> vet_addrs([ip])
          {:error, _} -> name |> resolve_all() |> vet_addrs()
        end
    end
  end

  defp vet_addrs([]), do: :unresolved

  defp vet_addrs(addrs) do
    case Enum.filter(addrs, &private_ip?/1) do
      [] -> {:ok, addrs}
      private -> {:private, private}
    end
  end

  @doc "Renders an IP tuple as its textual form."
  @spec ip_string(:inet.ip_address()) :: String.t()
  def ip_string(ip), do: ip |> :inet.ntoa() |> to_string()

  defp resolve_all(name) do
    [:inet, :inet6]
    |> Enum.flat_map(fn family ->
      case :inet.getaddrs(name, family, @dns_timeout_ms) do
        {:ok, addrs} -> addrs
        {:error, _} -> []
      end
    end)
    |> Enum.uniq()
  end

  @doc """
  True when `ip` is in a private or reserved range.

  IPv4: 0/8, 10/8, 100.64/10, 127/8, 169.254/16, 172.16/12, 192.0.0/24,
  192.0.2/24, 192.88.99/24, 192.168/16, 198.18/15, 198.51.100/24, 203.0.113/24,
  224/4 and 240/4. IPv6: `::`, `::1`, IPv4-mapped/compatible/translated and
  NAT64 `64:ff9b::/96` (embedded v4 checked), NAT64 local-use `64:ff9b:1::/48`,
  6to4 `2002::/16` (embedded v4 checked), Teredo `2001::/32`, documentation
  `2001:db8::/32`, `fc00::/7`, `fe80::/10` through `fec0::/10` and multicast
  `ff00::/8`.
  """
  @spec private_ip?(:inet.ip_address()) :: boolean()
  def private_ip?({0, _, _, _}), do: true
  def private_ip?({100, b, _, _}) when b in 64..127, do: true
  def private_ip?({127, _, _, _}), do: true
  def private_ip?({10, _, _, _}), do: true
  def private_ip?({172, b, _, _}) when b in 16..31, do: true
  def private_ip?({192, 168, _, _}), do: true
  def private_ip?({192, 0, 0, _}), do: true
  def private_ip?({192, 0, 2, _}), do: true
  def private_ip?({192, 88, 99, _}), do: true
  def private_ip?({198, 51, 100, _}), do: true
  def private_ip?({203, 0, 113, _}), do: true
  def private_ip?({198, b, _, _}) when b in 18..19, do: true
  def private_ip?({169, 254, _, _}), do: true
  # multicast 224/4 and reserved 240/4 (includes 255.255.255.255)
  def private_ip?({a, _, _, _}) when a >= 224, do: true
  def private_ip?({0, 0, 0, 0, 0, 0, 0, 0}), do: true
  def private_ip?({0, 0, 0, 0, 0, 0, 0, 1}), do: true

  # IPv4-mapped ::ffff:a.b.c.d and IPv4-compatible ::a.b.c.d
  def private_ip?({0, 0, 0, 0, 0, 0xFFFF, a, b}), do: private_ip?(v4(a, b))
  # IPv4-translated ::ffff:0:a.b.c.d (RFC 2765)
  def private_ip?({0, 0, 0, 0, 0xFFFF, 0, a, b}), do: private_ip?(v4(a, b))
  # NAT64 local-use 64:ff9b:1::/48
  def private_ip?({0x64, 0xFF9B, 1, _, _, _, _, _}), do: true
  # Teredo 2001::/32 and documentation 2001:db8::/32
  def private_ip?({0x2001, 0, _, _, _, _, _, _}), do: true
  def private_ip?({0x2001, 0xDB8, _, _, _, _, _, _}), do: true
  # multicast ff00::/8
  def private_ip?({w, _, _, _, _, _, _, _}) when w >= 0xFF00, do: true
  def private_ip?({0, 0, 0, 0, 0, 0, a, b}), do: private_ip?(v4(a, b))
  # NAT64 64:ff9b::/96
  def private_ip?({0x64, 0xFF9B, 0, 0, 0, 0, a, b}), do: private_ip?(v4(a, b))
  # 6to4 2002::/16 embeds the v4 address in bits 16..47
  def private_ip?({0x2002, a, b, _, _, _, _, _}), do: private_ip?(v4(a, b))
  # link-local fe80::/10 and deprecated site-local fec0::/10
  def private_ip?({w, _, _, _, _, _, _, _}) when w >= 0xFE80 and w <= 0xFEFF, do: true
  def private_ip?({w, _, _, _, _, _, _, _}) when w >= 0xFC00 and w <= 0xFDFF, do: true
  def private_ip?(_), do: false

  defp v4(a, b), do: {div(a, 256), rem(a, 256), div(b, 256), rem(b, 256)}
end
