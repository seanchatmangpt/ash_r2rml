# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.SPARQL.Protocol do
  @moduledoc """
  Read-only W3C SPARQL Protocol execution through SPARQL.Client.

  SPARQL.Client also implements update operations, but this module deliberately
  exposes queries only. Verification capability never manufactures remote
  mutation authority.

  Endpoint host vetting (fail-closed SSRF guard) lives in
  `AshR2RML.SPARQL.Protocol.Host`.
  """

  alias AshR2RML.Refusal
  alias AshR2RML.SPARQL.Protocol.Host
  alias AshR2RML.SPARQL.{Observation, Query, Result}

  @default_timeout_ms 30_000

  @doc """
  Options: `:timeout` (ms, default 30_000, always merged into the httpc adapter
  options as `:timeout` and `:connect_timeout`; `autoredirect: false` is always
  set), `:max_rows` (default #{Result.default_max_rows()}; exceeding it
  refuses with `:REFUSED_RESOURCE_BOUND`), `:allow_private_network`,
  `:follow_redirects` (default 0; a positive integer opts in to redirects, which
  are NOT re-vetted against the private-network guard), and the allowlisted
  SPARQL.Client options `:request_method`, `:protocol_version`,
  `:accept_header`, `:default_graph`, `:named_graph`, `:raw_mode`, plus
  `:request_opts`. Any other option (e.g. `:logger`, `:max_redirects`,
  `:headers`) is refused with `:REFUSED_INVALID_FEDERATION_ENVIRONMENT`
  (`evidence.unknown_options`), never silently dropped. A 3xx
  response with redirects disabled refuses with
  `:REFUSED_INVALID_FEDERATION_ENVIRONMENT` ("redirects are not followed").

  Private-network guard (`private_ip?/1`, see `AshR2RML.SPARQL.Protocol.Host`)
  covers: IPv4 0/8, 10/8, 100.64/10,
  127/8, 169.254/16, 172.16/12, 192.0.0/24, 192.0.2/24, 192.88.99/24,
  192.168/16, 198.18/15, 198.51.100/24, 203.0.113/24, 224/4 and 240/4; IPv6
  `::`, `::1`, IPv4-mapped/compatible/translated (`::ffff:0:a.b.c.d`) and
  NAT64 `64:ff9b::/96` (embedded v4 checked), NAT64 local-use `64:ff9b:1::/48`,
  6to4 `2002::/16` (embedded v4 checked), Teredo `2001::/32`, documentation
  `2001:db8::/32`, `fc00::/7`, `fe80::/10` through `fec0::/10` (to `feff`) and
  multicast `ff00::/8`. A trailing dot on hostnames is ignored.

  Endpoints carrying userinfo, a fragment or a query string are refused with
  `:REFUSED_INVALID_FEDERATION_ENVIRONMENT`.
  """
  @spec query(String.t(), String.t() | Query.t(), keyword()) ::
          {:ok, Observation.t()} | {:error, term()}
  def query(endpoint, query, opts \\ []) when is_binary(endpoint) do
    {allow_private, opts} = Keyword.pop(opts, :allow_private_network, false)

    with :ok <- validate_options(endpoint, opts),
         :ok <- validate_endpoint(endpoint, allow_private) do
      client_opts = client_opts(opts)

      do_query(
        endpoint,
        query,
        client_opts,
        &no_redirect_client/3,
        :sparql_protocol,
        :observed_remote_query
      )
    end
  end

  # SPARQL.Client.query/3 validates :max_redirects as :pos_integer, so 0 (no
  # redirects) cannot be passed through it. This drives the same
  # Request.build/Request.call pipeline directly (options are already
  # allowlisted by client_opts/1) so Tesla's FollowRedirects runs with
  # max_redirects: 0, which refuses to follow any 3xx.
  @doc false
  def no_redirect_client(%Elixir.SPARQL.Query{} = parsed, endpoint, opts) do
    with {:ok, request} <-
           Elixir.SPARQL.Client.Request.build(
             Elixir.SPARQL.Client.Query,
             parsed.form,
             parsed.query_string,
             endpoint,
             opts
           ) do
      case Elixir.SPARQL.Client.Request.call(request, opts) do
        {:ok, %{result: result}} ->
          {:ok, result}

        {:error, {Tesla.Middleware.FollowRedirects, :too_many_redirects}} ->
          {:error, redirect_refusal(endpoint)}

        {:error, %Elixir.SPARQL.Client.HTTPError{status: status}}
        when is_integer(status) and status in 300..399 ->
          {:error, redirect_refusal(endpoint)}

        other ->
          other
      end
    end
  end

  defp redirect_refusal(endpoint) do
    Refusal.new(
      :REFUSED_INVALID_FEDERATION_ENVIRONMENT,
      redact_uri_string(endpoint),
      "redirects are not followed",
      %{redirect: true}
    )
  end

  defp redact_uri_string(endpoint), do: endpoint |> URI.parse() |> redact_endpoint()

  @forwarded_opts [
    :request_method,
    :protocol_version,
    :accept_header,
    :default_graph,
    :named_graph,
    :raw_mode,
    :max_rows
  ]

  @accepted_opts [:timeout, :follow_redirects, :request_opts] ++ @forwarded_opts

  defp validate_options(endpoint, opts) do
    case Keyword.keys(opts) -- @accepted_opts do
      [] ->
        validate_timeout(endpoint, Keyword.get(opts, :timeout, @default_timeout_ms))

      unknown ->
        {:error,
         Refusal.new(
           :REFUSED_INVALID_FEDERATION_ENVIRONMENT,
           redact_uri_string(endpoint),
           "unknown SPARQL protocol options are refused, not dropped",
           %{unknown_options: Enum.uniq(unknown), accepted_options: @accepted_opts}
         )}
    end
  end

  # A non-positive-integer timeout (nil, :infinity, 0) would disable the explicit
  # request bound; refuse instead of forwarding it to httpc.
  defp validate_timeout(_endpoint, timeout) when is_integer(timeout) and timeout > 0, do: :ok

  defp validate_timeout(endpoint, timeout) do
    {:error,
     Refusal.new(
       :REFUSED_INVALID_FEDERATION_ENVIRONMENT,
       redact_uri_string(endpoint),
       "SPARQL protocol :timeout must be a positive integer (ms)",
       %{timeout: inspect(timeout)}
     )}
  end

  @doc false
  # Builds the option list handed to SPARQL.Client. Only allowlisted keys pass;
  # redirects are disabled (max_redirects: 0) unless the caller opts in with
  # `follow_redirects: n`; `:timeout` is always merged into request_opts.
  @spec client_opts(keyword()) :: keyword()
  def client_opts(opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout_ms)

    max_redirects =
      case Keyword.get(opts, :follow_redirects, 0) do
        n when is_integer(n) and n >= 0 -> n
        _ -> 0
      end

    caller_request_opts =
      case Keyword.get(opts, :request_opts, []) do
        list when is_list(list) -> list
        _ -> []
      end

    adapter =
      caller_request_opts
      |> Keyword.get(:adapter, [])
      |> then(&if(Keyword.keyword?(&1), do: &1, else: []))
      |> Keyword.put(:timeout, timeout)
      |> Keyword.put(:connect_timeout, timeout)
      |> Keyword.put(:autoredirect, false)

    request_opts = Keyword.put(caller_request_opts, :adapter, adapter)

    opts
    |> Keyword.take(@forwarded_opts)
    |> Keyword.put(:max_redirects, max_redirects)
    |> Keyword.put(:request_opts, request_opts)
  end

  defp validate_endpoint(endpoint, allow_private) do
    case URI.parse(endpoint) do
      %URI{scheme: scheme, host: host, userinfo: userinfo, fragment: fragment, query: query} = uri
      when scheme in ["http", "https"] and is_binary(host) and host != "" and
             (userinfo != nil or fragment != nil or query != nil) ->
        {:error,
         Refusal.new(
           :REFUSED_INVALID_FEDERATION_ENVIRONMENT,
           redact_endpoint(uri),
           "SPARQL endpoint must not carry userinfo, a fragment, or a query string",
           %{
             userinfo: userinfo != nil,
             fragment: fragment != nil,
             query: query != nil
           }
         )}

      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        if allow_private == true, do: :ok, else: vet_endpoint_host(endpoint, host)

      _ ->
        {:error,
         Refusal.new(
           :REFUSED_INVALID_FEDERATION_ENVIRONMENT,
           redact_uri_string(endpoint),
           "SPARQL endpoint must be an http or https URL with a non-empty host",
           %{allowed_schemes: ["http", "https"]}
         )}
    end
  end

  defp vet_endpoint_host(endpoint, host) do
    case Host.vet_host(host) do
      :ok ->
        :ok

      {:private, addrs} ->
        {:error,
         Refusal.new(
           :REFUSED_INVALID_FEDERATION_ENVIRONMENT,
           endpoint,
           "SPARQL endpoint resolves to a private network address; " <>
             "pass allow_private_network: true to permit",
           %{private_network: true, resolved: Enum.map(addrs, &Host.ip_string/1)}
         )}

      :unresolved ->
        {:error,
         Refusal.new(
           :REFUSED_INVALID_FEDERATION_ENVIRONMENT,
           endpoint,
           "SPARQL endpoint host did not resolve; refused fail-closed",
           %{private_network: false, dns_unresolved: true}
         )}
    end
  end

  # Drops userinfo, query and fragment so credentials never reach a Refusal.
  defp redact_endpoint(%URI{} = uri),
    do: URI.to_string(%URI{uri | userinfo: nil, query: nil, fragment: nil})

  @doc false
  @spec private_ip?(:inet.ip_address()) :: boolean()
  defdelegate private_ip?(ip), to: Host

  @doc "Injected client path for deterministic unit tests. Never a remote-query witness."
  @spec query_with(String.t(), String.t() | Query.t(), keyword(), function()) ::
          {:ok, Observation.t()} | {:error, term()}
  def query_with(endpoint, query, opts, client_fun)
      when is_binary(endpoint) and is_function(client_fun, 3) do
    do_query(endpoint, query, opts, client_fun, :injected_client, :test_double_only)
  end

  defp do_query(endpoint, query, opts, client_fun, evidence_kind, standing) do
    {max_rows, opts} = Keyword.pop(opts, :max_rows, Result.default_max_rows())

    with {:ok, admitted} <- Query.admit(query),
         {:ok, result} <- client_fun.(admitted.parsed, endpoint, opts),
         {:ok, result_kind, rows} <-
           result |> Result.normalize() |> Result.bound(endpoint, max_rows) do
      {:ok,
       %Observation{
         strategy: :protocol,
         query_sha256: admitted.sha256,
         query_form: admitted.form,
         status: :PARTIAL_ALIVE,
         standing: standing,
         evidence_kind: evidence_kind,
         endpoint: endpoint,
         result_kind: result_kind,
         result_sha256: Result.hash_rows(rows),
         rows: rows,
         metadata: %{client: :sparql_client}
       }}
    else
      {:error, reason} ->
        {:error, reason}

      other ->
        {:error,
         Refusal.new(
           :REFUSED_UNPROVEN_EQUIVALENCE,
           endpoint,
           "SPARQL protocol client returned an unrecognized result",
           %{result: inspect(other)}
         )}
    end
  rescue
    exception ->
      {:error,
       Refusal.new(
         :REFUSED_UNPROVEN_EQUIVALENCE,
         endpoint,
         "SPARQL protocol query raised",
         %{exception: Exception.message(exception)}
       )}
  end
end
