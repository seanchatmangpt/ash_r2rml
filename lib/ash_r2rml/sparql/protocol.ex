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

  alias AshR2RML.OBDA.Worker
  alias AshR2RML.Refusal
  alias AshR2RML.SPARQL.Protocol.Host
  alias AshR2RML.SPARQL.{Observation, Query, Result}

  @default_timeout_ms 30_000
  @worker_grace_ms 5_000
  @max_heap_words 10_000_000

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

  Option values are validated before any network I/O: `:allow_private_network`
  must be a boolean, `:follow_redirects` a non-negative integer, `:request_opts`
  (and its `:adapter`) a keyword list (each refused with
  `:REFUSED_INVALID_FEDERATION_ENVIRONMENT`), and `:max_rows` a positive integer
  (`:REFUSED_RESOURCE_BOUND`).

  Transport pins the vetted address: a hostname is resolved once by the vetting
  step and the request connects to that address, sending the original host as
  the `Host` header (and as verified TLS SNI for https). Client call and response
  normalization run in a heap-capped worker; only transport/parse exceptions are
  refused (naming `exception_module`), programmer errors propagate.

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

    with :ok <- validate_allow_private(endpoint, allow_private),
         :ok <- validate_options(endpoint, opts),
         {:ok, pin} <- validate_endpoint(endpoint, allow_private) do
      client_opts = opts |> client_opts() |> apply_pin(pin)
      transport_url = pinned_url(endpoint, pin)
      client = fn parsed, _endpoint, o -> no_redirect_client(parsed, transport_url, o) end

      do_query(endpoint, query, client_opts, client, :sparql_protocol, :observed_remote_query)
    end
  end

  # Address pinning (DNS-rebinding guard): the vetted address is the one the
  # request connects to; the original host travels as the Host header and, for
  # https, as TLS SNI with hostname verification against the original name.
  defp pinned_url(endpoint, nil), do: endpoint

  defp pinned_url(endpoint, %{ip: ip}) do
    uri = URI.parse(endpoint)
    host = Host.ip_string(ip)
    host = if tuple_size(ip) == 8, do: "[" <> host <> "]", else: host
    URI.to_string(%URI{uri | host: host, authority: nil})
  end

  defp apply_pin(client_opts, nil), do: client_opts

  defp apply_pin(client_opts, %{host: host, host_header: host_header, scheme: scheme}) do
    request_opts = Keyword.fetch!(client_opts, :request_opts)
    adapter = Keyword.fetch!(request_opts, :adapter)

    adapter =
      if scheme == "https" do
        Keyword.put(adapter, :ssl, tls_opts(Keyword.get(adapter, :ssl, []), host))
      else
        adapter
      end

    client_opts
    |> Keyword.put(:headers, %{"Host" => host_header})
    |> Keyword.put(:request_opts, Keyword.put(request_opts, :adapter, adapter))
  end

  defp tls_opts(caller_ssl, host) do
    caller_ssl = if Keyword.keyword?(caller_ssl), do: caller_ssl, else: []

    caller_ssl
    |> Keyword.merge(
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      server_name_indication: String.to_charlist(host),
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    )
  end

  # SPARQL.Client.query/3 validates :max_redirects as :pos_integer, so 0 (no
  # redirects) cannot be passed through it. This drives the same
  # Request.build/Request.call pipeline directly (options are already
  # allowlisted by client_opts/1) so Tesla's FollowRedirects runs with
  # max_redirects: 0, which refuses to follow any 3xx.
  @doc false
  def no_redirect_client(%Elixir.SPARQL.Query{} = parsed, endpoint, opts) do
    # :timeout is kept in client_opts for the worker deadline; the adapter carries its own copy.
    opts = Keyword.delete(opts, :timeout)

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
        with :ok <- validate_timeout(endpoint, Keyword.get(opts, :timeout, @default_timeout_ms)),
             :ok <- validate_follow_redirects(endpoint, Keyword.get(opts, :follow_redirects, 0)),
             :ok <- validate_request_opts(endpoint, Keyword.get(opts, :request_opts, [])) do
          validate_max_rows(endpoint, Keyword.get(opts, :max_rows, Result.default_max_rows()))
        end

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

  defp validate_allow_private(_endpoint, value) when is_boolean(value), do: :ok

  defp validate_allow_private(endpoint, value) do
    invalid_env(endpoint, ":allow_private_network must be a boolean", %{
      allow_private_network: inspect(value)
    })
  end

  defp validate_follow_redirects(_endpoint, n) when is_integer(n) and n >= 0, do: :ok

  defp validate_follow_redirects(endpoint, value) do
    invalid_env(endpoint, ":follow_redirects must be a non-negative integer", %{
      follow_redirects: inspect(value)
    })
  end

  defp validate_request_opts(endpoint, request_opts) do
    adapter = if Keyword.keyword?(request_opts), do: Keyword.get(request_opts, :adapter, []), else: []

    if Keyword.keyword?(request_opts) and Keyword.keyword?(adapter) do
      :ok
    else
      invalid_env(endpoint, ":request_opts (and its :adapter) must be a keyword list", %{
        request_opts: inspect(request_opts)
      })
    end
  end

  defp validate_max_rows(_endpoint, n) when is_integer(n) and n > 0, do: :ok

  defp validate_max_rows(endpoint, value) do
    {:error,
     Refusal.new(
       :REFUSED_RESOURCE_BOUND,
       redact_uri_string(endpoint),
       "SPARQL protocol :max_rows must be a positive integer",
       %{max_rows: inspect(value)}
     )}
  end

  defp invalid_env(endpoint, detail, evidence) do
    {:error,
     Refusal.new(
       :REFUSED_INVALID_FEDERATION_ENVIRONMENT,
       redact_uri_string(endpoint),
       detail,
       evidence
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
    |> Keyword.put(:timeout, timeout)
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

      %URI{scheme: scheme, host: host} = uri
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        if allow_private == true, do: {:ok, nil}, else: vet_endpoint_host(endpoint, uri)

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

  defp vet_endpoint_host(endpoint, %URI{host: host} = uri) do
    case Host.vet(host) do
      {:ok, [ip | _]} ->
        {:ok, pin_for(uri, host, ip)}

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

  # A literal-IP host is its own pin; a name is pinned to its first vetted address.
  defp pin_for(%URI{scheme: scheme, port: port}, host, ip) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, _literal} ->
        nil

      {:error, _} ->
        host_header = if port == URI.default_port(scheme), do: host, else: "#{host}:#{port}"
        %{ip: ip, host: host, host_header: host_header, scheme: scheme}
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

    with :ok <- validate_max_rows(endpoint, max_rows),
         {:ok, admitted} <- Query.admit(query),
         {:ok, result_kind, rows} <- fetch(admitted, endpoint, opts, client_fun, max_rows),
         {:ok, result_kind, rows} <-
           Result.bound({:ok, result_kind, rows}, endpoint, max_rows) do
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
  end

  # The client call and response normalization run in a heap-capped, monitored
  # worker (remote response parsing is isolated from the caller). Only transport
  # and parse boundary exceptions are refused; anything else is re-raised here.
  defp fetch(admitted, endpoint, opts, client_fun, max_rows) do
    timeout =
      case Keyword.get(opts, :timeout, @default_timeout_ms) do
        t when is_integer(t) and t > 0 -> t
        _ -> @default_timeout_ms
      end

    worker_opts = [timeout_ms: timeout + @worker_grace_ms, max_heap_words: @max_heap_words]

    case Worker.call(fn -> call_client(admitted, endpoint, opts, client_fun, max_rows) end, worker_opts) do
      {:ok, {:boundary_error, exception}} ->
        {:error,
         Refusal.new(
           :REFUSED_UNPROVEN_EQUIVALENCE,
           endpoint,
           "SPARQL protocol query raised",
           %{exception: Exception.message(exception), exception_module: inspect(exception.__struct__)}
         )}

      {:ok, outcome} ->
        outcome

      {:raised, kind, reason, stacktrace} ->
        :erlang.raise(kind, reason, stacktrace)

      {:error, %AshR2RML.Error{code: code, message: message}} ->
        {:error,
         Refusal.new(
           :REFUSED_RESOURCE_BOUND,
           endpoint,
           "SPARQL protocol response handling exceeded its isolation bound: #{message}",
           %{worker_code: code}
         )}
    end
  end

  # The row bound is enforced here, inside the worker, so an oversized result is refused
  # before it is copied across the process boundary into the caller's heap.
  defp call_client(admitted, endpoint, opts, client_fun, max_rows) do
    case client_fun.(admitted.parsed, endpoint, opts) do
      {:ok, result} ->
        with {:ok, kind, rows} <- Result.normalize(result) do
          Result.bound({:ok, kind, rows}, endpoint, max_rows)
        end

      other ->
        other
    end
  rescue
    exception in [Tesla.Error, Elixir.SPARQL.Client.HTTPError, ArgumentError, RuntimeError] ->
      {:boundary_error, exception}
  end
end
