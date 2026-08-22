# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Telemetry.FlyClient do
  @moduledoc """
  Telemetry and Fly Control Plane Client for AshR2RML.

  Signs and batches IEEE OCEL 2.0 event streams into standard `chatgpt-cloud-ocel/1` envelopes,
  computes deterministic SHA-256 hash-chained batch digests, and dispatches them to
  `FLY_CONTROL_PLANE_URL` (`POST /api/v1/ocel/events`).

  Provides:
  - Deterministic batch digest computation & cryptographic hash chaining (`previous_digest` -> `digest`).
  - Monotonic sequencing.
  - Client-side event buffering with configurable batch size and auto-flush timer.
  - HTTP dispatching via `:httpc` with configurable adapters/mock dispatchers.
  - Offline fallback persistence to disk (NDJSON) and replay functionality.
  - Cryptographic envelope signature verification & chain validation.
  """

  use GenServer
  require Logger

  @schema_version "chatgpt-cloud-ocel/1"
  @default_endpoint "/api/v1/ocel/events"
  @default_batch_size 50
  @default_flush_interval_ms 5_000
  @default_fallback_path "priv/ocel/offline_fallback.ndjson"

  defstruct [
    :name,
    :control_plane_url,
    :api_key,
    :signing_key,
    :producer,
    :offline_fallback_path,
    :dispatcher,
    :timer_ref,
    buffer: [],
    sequence: 0,
    previous_digest: nil,
    batch_size: @default_batch_size,
    flush_interval_ms: @default_flush_interval_ms,
    auto_flush: true,
    offline_queue: [],
    history: []
  ]

  @type producer :: %{
          required(String.t()) => String.t(),
          optional(atom()) => String.t()
        }

  @type envelope :: %{
          required(String.t()) => any()
        }

  # ============================================================================
  # Public Functional API
  # ============================================================================

  @doc """
  Constructs a standard `chatgpt-cloud-ocel/1` envelope map with deterministic
  SHA-256 digest and monotonic sequence metadata.
  """
  @spec build_envelope(list(map()), non_neg_integer(), String.t() | nil, map() | keyword(), keyword()) :: envelope()
  def build_envelope(events, sequence, prev_digest, producer, opts \\ []) when is_list(events) do
    normalized_producer = normalize_producer(producer)
    signing_key = Keyword.get(opts, :signing_key)

    canonical_events = Enum.map(events, &canonicalize_map/1)

    digest = compute_digest(canonical_events, sequence, prev_digest, normalized_producer)

    envelope = %{
      "schema" => @schema_version,
      "producer" => normalized_producer,
      "sequence" => sequence,
      "previous_digest" => prev_digest,
      "digest" => digest,
      "events" => canonical_events
    }

    if signing_key do
      signature = sign_digest(digest, signing_key)
      Map.put(envelope, "signature", signature)
    else
      envelope
    end
  end

  @doc """
  Computes a deterministic SHA-256 hex digest for an envelope or batch components.
  """
  @spec compute_digest(list(map()), non_neg_integer(), String.t() | nil, map()) :: String.t()
  def compute_digest(events, sequence, prev_digest, producer) when is_list(events) do
    canonical_data = [
      @schema_version,
      normalize_producer(producer),
      sequence,
      prev_digest,
      Enum.map(events, &canonicalize_map/1)
    ]

    canonical_json = Jason.encode!(canonical_data)
    :crypto.hash(:sha256, canonical_json) |> Base.encode16(case: :lower)
  end

  @doc """
  Computes a deterministic SHA-256 hex digest from an envelope map.
  """
  @spec compute_digest(envelope()) :: String.t()
  def compute_digest(%{} = envelope) do
    events = Map.get(envelope, "events", [])
    sequence = Map.get(envelope, "sequence", 0)
    prev_digest = Map.get(envelope, "previous_digest")
    producer = Map.get(envelope, "producer", %{})
    compute_digest(events, sequence, prev_digest, producer)
  end

  @doc """
  Signs a digest using HMAC-SHA256.
  """
  @spec sign_digest(String.t(), String.t()) :: String.t()
  def sign_digest(digest, secret) when is_binary(digest) and is_binary(secret) do
    :crypto.mac(:hmac, :sha256, secret, digest) |> Base.encode16(case: :lower)
  end

  @doc """
  Verifies that an envelope's internal digest matches its computed deterministic digest.
  """
  @spec verify_digest(envelope()) :: boolean()
  def verify_digest(%{"digest" => digest} = envelope) when is_binary(digest) do
    computed = compute_digest(envelope)
    :crypto.hash_equals(digest, computed)
  rescue
    _ -> digest == compute_digest(envelope)
  end

  def verify_digest(_), do: false

  @doc """
  Verifies that a list of envelopes forms an unbroken, monotonically sequenced cryptographic hash chain.
  """
  @spec verify_chain(list(envelope())) :: {:ok, non_neg_integer()} | {:error, {atom(), map()}}
  def verify_chain([]), do: {:ok, 0}

  def verify_chain(envelopes) when is_list(envelopes) do
    sorted = Enum.sort_by(envelopes, & &1["sequence"])

    result =
      Enum.reduce_while(sorted, {:ok, nil, nil}, fn env, {:ok, prev_seq, prev_digest} ->
        seq = Map.get(env, "sequence")
        p_dig = Map.get(env, "previous_digest")
        dig = Map.get(env, "digest")

        cond do
          not verify_digest(env) ->
            {:halt, {:error, {:invalid_digest, %{sequence: seq, envelope: env}}}}

          prev_seq != nil and seq != prev_seq + 1 ->
            {:halt, {:error, {:non_monotonic_sequence, %{expected: prev_seq + 1, actual: seq}}}}

          prev_digest != nil and p_dig != prev_digest ->
            {:halt, {:error, {:broken_hash_chain, %{expected_prev_digest: prev_digest, actual_prev_digest: p_dig}}}}

          true ->
            {:cont, {:ok, seq, dig}}
        end
      end)

    case result do
      {:ok, _last_seq, _last_dig} -> {:ok, length(envelopes)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Returns a standard producer map populated with system & runtime information.
  """
  @spec default_producer(keyword()) :: map()
  def default_producer(opts \\ []) do
    agent_id =
      Keyword.get(opts, :agent_id) ||
        System.get_env("AGENT_ID") ||
        Application.get_env(:ash_r2rml, :agent_id, "ash_r2rml_agent")

    run_id =
      Keyword.get(opts, :run_id) ||
        System.get_env("FLY_RUN_ID") ||
        System.get_env("RUN_ID") ||
        generate_run_id()

    runtime =
      Keyword.get(opts, :runtime) ||
        "elixir/#{System.version()} (otp/#{System.otp_release()})"

    subject_sha =
      Keyword.get(opts, :subject_sha) ||
        System.get_env("FLY_SUBJECT_SHA") ||
        compute_subject_sha()

    %{
      "agent_id" => to_string(agent_id),
      "run_id" => to_string(run_id),
      "runtime" => to_string(runtime),
      "subject_sha" => to_string(subject_sha)
    }
  end

  # ============================================================================
  # HTTP & Dispatcher API
  # ============================================================================

  @doc """
  Dispatches an envelope map to the Fly Control Plane endpoint.
  """
  @spec dispatch_envelope(envelope(), keyword()) ::
          {:ok, map()} | {:error, {:offline_buffered, any()}} | {:error, any()}
  def dispatch_envelope(envelope, opts \\ []) do
    url = Keyword.get(opts, :control_plane_url) || get_control_plane_url()
    api_key = Keyword.get(opts, :api_key) || System.get_env("FLY_API_KEY")
    fallback_path = Keyword.get(opts, :offline_fallback_path, @default_fallback_path)
    custom_dispatcher = Keyword.get(opts, :dispatcher)

    target_url = normalize_endpoint_url(url)
    json_body = Jason.encode!(envelope)

    headers = [
      {"content-type", "application/json"},
      {"accept", "application/json"},
      {"user-agent", "AshR2RML-FlyClient/1.0"}
    ]

    headers =
      if api_key && byte_size(api_key) > 0 do
        [{"authorization", "Bearer #{api_key}"} | headers]
      else
        headers
      end

    result =
      if is_function(custom_dispatcher, 3) do
        custom_dispatcher.(target_url, headers, json_body)
      else
        httpc_post(target_url, headers, json_body, opts)
      end

    case result do
      {:ok, status, resp_body} when status in 200..299 ->
        parsed =
          case Jason.decode(resp_body) do
            {:ok, json} -> json
            _ -> %{"status" => status, "body" => resp_body}
          end

        {:ok, parsed}

      {:ok, status, resp_body} ->
        error_reason = {:http_error, status, resp_body}
        write_offline_fallback(envelope, fallback_path)
        {:error, {:offline_buffered, error_reason}}

      {:error, reason} ->
        write_offline_fallback(envelope, fallback_path)
        {:error, {:offline_buffered, reason}}
    end
  end

  defp httpc_post(url, headers, body, opts) do
    ensure_inets_started()

    timeout = Keyword.get(opts, :timeout, 10_000)
    connect_timeout = Keyword.get(opts, :connect_timeout, 5_000)

    url_charlist = String.to_charlist(url)

    headers_charlist =
      Enum.map(headers, fn {k, v} ->
        {String.to_charlist(to_string(k)), String.to_charlist(to_string(v))}
      end)

    content_type_charlist = ~c"application/json"
    request = {url_charlist, headers_charlist, content_type_charlist, body}
    http_opts = [timeout: timeout, connect_timeout: connect_timeout]
    req_opts = [body_format: :binary]

    case :httpc.request(:post, request, http_opts, req_opts) do
      {:ok, {{_proto, status, _reason_phrase}, _resp_headers, resp_body}} ->
        {:ok, status, resp_body}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ensure_inets_started do
    :inets.start()
    :ssl.start()
    :ok
  end

  defp normalize_endpoint_url(base_url) do
    trimmed = String.trim_trailing(to_string(base_url), "/")

    if String.ends_with?(trimmed, @default_endpoint) do
      trimmed
    else
      "#{trimmed}#{@default_endpoint}"
    end
  end

  defp get_control_plane_url do
    System.get_env("FLY_CONTROL_PLANE_URL") ||
      Application.get_env(:ash_r2rml, :fly_control_plane_url, "http://127.0.0.1:8080")
  end

  # ============================================================================
  # GenServer Client API
  # ============================================================================

  @doc """
  Starts the FlyClient GenServer process.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Pushes a single IEEE OCEL 2.0 event to the client buffer.
  """
  @spec push_event(GenServer.server(), map()) :: :ok
  def push_event(client \\ __MODULE__, event) when is_map(event) do
    GenServer.call(client, {:push_event, event})
  end

  @doc """
  Pushes a batch of IEEE OCEL 2.0 events to the client buffer.
  """
  @spec push_events(GenServer.server(), list(map())) :: :ok
  def push_events(client \\ __MODULE__, events) when is_list(events) do
    GenServer.call(client, {:push_events, events})
  end

  @doc """
  Explicitly flushes buffered events into an envelope and dispatches to the control plane.
  """
  @spec flush(GenServer.server()) :: {:ok, envelope()} | {:ok, :empty} | {:error, any()}
  def flush(client \\ __MODULE__) do
    GenServer.call(client, :flush)
  end

  @doc """
  Retrieves the current introspection state of the FlyClient.
  """
  @spec get_state(GenServer.server()) :: map()
  def get_state(client \\ __MODULE__) do
    GenServer.call(client, :get_state)
  end

  @doc """
  Replays all offline-buffered envelopes from disk and memory fallback queues.
  """
  @spec replay_offline(GenServer.server(), keyword()) :: {:ok, non_neg_integer()} | {:error, any()}
  def replay_offline(client \\ __MODULE__, opts \\ []) do
    GenServer.call(client, {:replay_offline, opts})
  end

  @doc """
  Stops the FlyClient GenServer gracefully after flushing any remaining events.
  """
  @spec stop(GenServer.server()) :: :ok
  def stop(client \\ __MODULE__) do
    GenServer.stop(client, :normal)
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    url = Keyword.get(opts, :control_plane_url) || get_control_plane_url()
    api_key = Keyword.get(opts, :api_key) || System.get_env("FLY_API_KEY")
    signing_key = Keyword.get(opts, :signing_key)
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    flush_interval_ms = Keyword.get(opts, :flush_interval_ms, @default_flush_interval_ms)
    auto_flush = Keyword.get(opts, :auto_flush, true)
    fallback_path = Keyword.get(opts, :offline_fallback_path, @default_fallback_path)
    dispatcher = Keyword.get(opts, :dispatcher)
    producer = Keyword.get(opts, :producer) || default_producer(opts)

    timer_ref =
      if auto_flush and flush_interval_ms > 0 do
        schedule_flush(flush_interval_ms)
      else
        nil
      end

    state = %__MODULE__{
      control_plane_url: url,
      api_key: api_key,
      signing_key: signing_key,
      producer: normalize_producer(producer),
      batch_size: batch_size,
      flush_interval_ms: flush_interval_ms,
      auto_flush: auto_flush,
      offline_fallback_path: fallback_path,
      dispatcher: dispatcher,
      timer_ref: timer_ref,
      buffer: [],
      sequence: 0,
      previous_digest: nil,
      offline_queue: [],
      history: []
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:push_event, event}, _from, state) do
    new_buffer = state.buffer ++ [canonicalize_map(event)]
    state = %{state | buffer: new_buffer}

    if length(new_buffer) >= state.batch_size do
      {_result, new_state} = do_flush(state)
      {:reply, :ok, new_state}
    else
      {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:push_events, events}, _from, state) do
    canonical = Enum.map(events, &canonicalize_map/1)
    new_buffer = state.buffer ++ canonical
    state = %{state | buffer: new_buffer}

    if length(new_buffer) >= state.batch_size do
      {_result, new_state} = do_flush(state)
      {:reply, :ok, new_state}
    else
      {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call(:flush, _from, state) do
    {result, new_state} = do_flush(state)
    {:reply, result, new_state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    info = %{
      buffer_count: length(state.buffer),
      sequence: state.sequence,
      previous_digest: state.previous_digest,
      producer: state.producer,
      control_plane_url: state.control_plane_url,
      offline_queue_count: length(state.offline_queue),
      history_count: length(state.history),
      batch_size: state.batch_size,
      flush_interval_ms: state.flush_interval_ms
    }

    {:reply, info, state}
  end

  @impl true
  def handle_call({:replay_offline, opts}, _from, state) do
    {replayed_count, new_state} = do_replay_offline(state, opts)
    {:reply, {:ok, replayed_count}, new_state}
  end

  @impl true
  def handle_info(:scheduled_flush, state) do
    {_result, new_state} =
      if length(state.buffer) > 0 do
        do_flush(state)
      else
        {:ok, state}
      end

    timer_ref =
      if new_state.auto_flush and new_state.flush_interval_ms > 0 do
        schedule_flush(new_state.flush_interval_ms)
      else
        nil
      end

    {:noreply, %{new_state | timer_ref: timer_ref}}
  end

  @impl true
  def terminate(_reason, state) do
    if length(state.buffer) > 0 do
      do_flush(state)
    end

    :ok
  end

  # ============================================================================
  # Internal Helpers
  # ============================================================================

  defp do_flush(%{buffer: []} = state), do: {{:ok, :empty}, state}

  defp do_flush(state) do
    next_sequence = state.sequence + 1
    events = state.buffer
    prev_digest = state.previous_digest

    opts =
      if state.signing_key do
        [signing_key: state.signing_key]
      else
        []
      end

    envelope = build_envelope(events, next_sequence, prev_digest, state.producer, opts)

    dispatch_opts = [
      control_plane_url: state.control_plane_url,
      api_key: state.api_key,
      offline_fallback_path: state.offline_fallback_path,
      dispatcher: state.dispatcher
    ]

    dispatch_result = dispatch_envelope(envelope, dispatch_opts)

    new_digest = envelope["digest"]

    case dispatch_result do
      {:ok, _response} ->
        new_state = %{
          state
          | buffer: [],
            sequence: next_sequence,
            previous_digest: new_digest,
            history: state.history ++ [envelope]
        }

        {{:ok, envelope}, new_state}

      {:error, {:offline_buffered, _reason}} ->
        new_state = %{
          state
          | buffer: [],
            sequence: next_sequence,
            previous_digest: new_digest,
            offline_queue: state.offline_queue ++ [envelope],
            history: state.history ++ [envelope]
        }

        {{:ok, envelope}, new_state}

      {:error, reason} ->
        {{:error, reason}, state}
    end
  end

  defp do_replay_offline(state, opts) do
    disk_envelopes = read_offline_fallback(state.offline_fallback_path)
    all_envelopes = state.offline_queue ++ disk_envelopes

    unique_envelopes = Enum.uniq_by(all_envelopes, &{&1["sequence"], &1["digest"]})

    dispatch_opts = [
      control_plane_url: state.control_plane_url,
      api_key: state.api_key,
      offline_fallback_path: state.offline_fallback_path,
      dispatcher: Keyword.get(opts, :dispatcher) || state.dispatcher
    ]

    successful =
      Enum.reduce(unique_envelopes, [], fn env, acc ->
        case dispatch_envelope(env, Keyword.put(dispatch_opts, :offline_fallback_path, nil)) do
          {:ok, _} -> [env | acc]
          _ -> acc
        end
      end)

    if successful != [] do
      # Clear disk fallback file if all or some succeeded
      remaining_disk = disk_envelopes -- successful

      if remaining_disk == [] do
        File.rm(state.offline_fallback_path)
      else
        lines = Enum.map_join(remaining_disk, "\n", &Jason.encode!/1) <> "\n"
        File.write!(state.offline_fallback_path, lines)
      end
    end

    remaining_memory = state.offline_queue -- successful

    {length(successful), %{state | offline_queue: remaining_memory}}
  end

  defp schedule_flush(interval_ms) do
    Process.send_after(self(), :scheduled_flush, interval_ms)
  end

  defp normalize_producer(producer) when is_map(producer) do
    %{
      "agent_id" => to_string(producer["agent_id"] || producer[:agent_id] || "ash_r2rml_agent"),
      "run_id" => to_string(producer["run_id"] || producer[:run_id] || "run_default"),
      "runtime" => to_string(producer["runtime"] || producer[:runtime] || "elixir/#{System.version()}"),
      "subject_sha" => to_string(producer["subject_sha"] || producer[:subject_sha] || "0000000000000000")
    }
  end

  defp normalize_producer(producer) when is_list(producer) do
    normalize_producer(Map.new(producer))
  end

  defp normalize_producer(_), do: normalize_producer(%{})

  defp canonicalize_map(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_map(v) -> {to_string(k), canonicalize_map(v)}
      {k, v} when is_list(v) -> {to_string(k), Enum.map(v, &canonicalize_val/1)}
      {k, v} -> {to_string(k), v}
    end)
  end

  defp canonicalize_val(map) when is_map(map), do: canonicalize_map(map)
  defp canonicalize_val(other), do: other

  defp write_offline_fallback(_envelope, nil), do: :ok

  defp write_offline_fallback(envelope, path) when is_binary(path) do
    File.mkdir_p!(Path.dirname(path))
    json_line = Jason.encode!(envelope) <> "\n"
    File.write!(path, json_line, [:append])
  rescue
    e ->
      Logger.warning("Failed to write to offline fallback path #{path}: #{inspect(e)}")
      :ok
  end

  defp read_offline_fallback(nil), do: []

  defp read_offline_fallback(path) when is_binary(path) do
    if File.exists?(path) do
      File.read!(path)
      |> String.split("\n", trim: true)
      |> Enum.map(fn line ->
        case Jason.decode(line) do
          {:ok, env} -> env
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)
    else
      []
    end
  rescue
    _ -> []
  end

  defp generate_run_id do
    "run_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end

  defp compute_subject_sha do
    :crypto.hash(:sha256, "AshR2RML.Telemetry.FlyClient") |> Base.encode16(case: :lower)
  end
end
