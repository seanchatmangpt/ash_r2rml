# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RedProtocolOptsTest do
  @moduledoc """
  Red-before-green courts for SPARQL protocol option validation (H31) and
  vetted-address pinning (H43).
  """
  use ExUnit.Case, async: true

  alias AshR2RML.Refusal
  alias AshR2RML.SPARQL.Protocol

  @query "SELECT * WHERE { ?s ?p ?o }"
  @public "http://endpoint.invalid/sparql"
  @private "http://127.0.0.1:9/sparql"

  defp refused_env?(result) do
    match?({:error, %Refusal{code: :REFUSED_INVALID_FEDERATION_ENVIRONMENT}}, result)
  end

  test "H31 follow_redirects true is refused, not coerced to 0" do
    assert refused_env?(Protocol.query(@public, @query, follow_redirects: true))
  end

  test "H31 follow_redirects -1 is refused, not coerced to 0" do
    assert refused_env?(Protocol.query(@public, @query, follow_redirects: -1))
  end

  test "H31 non-list request_opts is refused, not coerced to []" do
    assert refused_env?(Protocol.query(@public, @query, request_opts: :bad))
  end

  test "H31 non-keyword request_opts adapter is refused, not coerced to []" do
    opts = [request_opts: [adapter: :not_a_keyword]]
    assert refused_env?(Protocol.query(@public, @query, opts))
  end

  test "H31 non-boolean allow_private_network is refused as an invalid option" do
    result = Protocol.query(@private, @query, allow_private_network: :yes)
    assert {:error, %Refusal{code: :REFUSED_INVALID_FEDERATION_ENVIRONMENT} = r} = result
    refute Map.get(r.evidence, :private_network) == true
  end

  test "H43 vetted address is pinned for transport, not re-resolved by hostname" do
    source = File.read!(Path.expand("../lib/ash_r2rml/sparql/protocol.ex", __DIR__))

    # Vetting must hand its resolved address to the transport: the vet result
    # cannot be reduced to a bare :ok that is discarded before the request.
    refute source =~ ~r/Host\.vet_host\(host\)\s*do\s*\n\s*:ok ->\s*\n\s*:ok\b/,
           "vet_host result is discarded as :ok; transport re-resolves the hostname"

    assert source =~ ~r/pin/i
  end
end
