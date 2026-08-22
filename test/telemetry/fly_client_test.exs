# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Telemetry.FlyClientTest do
  use ExUnit.Case, async: false

  alias AshR2RML.Telemetry.FlyClient

  @sample_producer %{
    "agent_id" => "agent_test_42",
    "run_id" => "run_test_abc",
    "runtime" => "elixir/1.18",
    "subject_sha" => "fedcba9876543210"
  }

  @sample_event_1 %{
    "ocel:eid" => "018f3a5e-7a2e-7411-9a99-0123456789ab",
    "ocel:activity" => "organization.create",
    "ocel:timestamp" => "2026-08-21T18:00:00Z",
    "ocel:omap" => ["organization:org_1"],
    "ocel:vmap" => %{"name" => "Acme Labs", "outcome" => "stop"}
  }

  @sample_event_2 %{
    "ocel:eid" => "018f3a5e-7a2e-7411-9a99-0123456789ac",
    "ocel:activity" => "person.create",
    "ocel:timestamp" => "2026-08-21T18:00:01Z",
    "ocel:omap" => ["person:person_1", "organization:org_1"],
    "ocel:vmap" => %{"name" => "Dr. Alice", "outcome" => "stop"}
  }

  setup do
    test_fallback = Path.join(["tmp", "test_offline_fallback_#{System.unique_integer([:positive])}.ndjson"])
    File.rm(test_fallback)
    File.mkdir_p!(Path.dirname(test_fallback))

    on_exit(fn ->
      File.rm(test_fallback)
    end)

    {:ok, fallback_path: test_fallback}
  end

  describe "Envelope Construction & Schema" do
    test "constructs standard chatgpt-cloud-ocel/1 envelope with required fields" do
      envelope = FlyClient.build_envelope([@sample_event_1], 1, nil, @sample_producer)

      assert envelope["schema"] == "chatgpt-cloud-ocel/1"
      assert envelope["sequence"] == 1
      assert envelope["previous_digest"] == nil
      assert is_binary(envelope["digest"])
      assert String.length(envelope["digest"]) == 64
      assert envelope["producer"]["agent_id"] == "agent_test_42"
      assert envelope["producer"]["run_id"] == "run_test_abc"
      assert envelope["producer"]["runtime"] == "elixir/1.18"
      assert envelope["producer"]["subject_sha"] == "fedcba9876543210"
      assert length(envelope["events"]) == 1
      assert List.first(envelope["events"])["ocel:activity"] == "organization.create"
    end

    test "attaches HMAC-SHA256 signature when signing_key is provided" do
      secret = "top_secret_fly_key"
      envelope = FlyClient.build_envelope([@sample_event_1], 1, nil, @sample_producer, signing_key: secret)

      assert is_binary(envelope["signature"])
      expected_sig = FlyClient.sign_digest(envelope["digest"], secret)
      assert envelope["signature"] == expected_sig
    end

    test "default_producer populates default runtime and environment metadata" do
      producer = FlyClient.default_producer(agent_id: "custom_agent")
      assert producer["agent_id"] == "custom_agent"
      assert is_binary(producer["run_id"])
      assert String.starts_with?(producer["runtime"], "elixir/")
      assert is_binary(producer["subject_sha"])
    end
  end

  describe "Deterministic SHA-256 Batch Digest & Verification" do
    test "computes deterministic digest identical across identical batch data" do
      digest1 = FlyClient.compute_digest([@sample_event_1, @sample_event_2], 1, nil, @sample_producer)
      digest2 = FlyClient.compute_digest([@sample_event_1, @sample_event_2], 1, nil, @sample_producer)

      assert digest1 == digest2
      assert is_binary(digest1)
      assert String.length(digest1) == 64
    end

    test "altering any field alters the computed digest" do
      base = FlyClient.compute_digest([@sample_event_1], 1, nil, @sample_producer)

      altered_event = Map.put(@sample_event_1, "ocel:activity", "organization.update")
      diff_event = FlyClient.compute_digest([altered_event], 1, nil, @sample_producer)
      assert base != diff_event

      diff_seq = FlyClient.compute_digest([@sample_event_1], 2, nil, @sample_producer)
      assert base != diff_seq

      diff_prev = FlyClient.compute_digest([@sample_event_1], 1, "00001111", @sample_producer)
      assert base != diff_prev

      diff_producer = FlyClient.compute_digest([@sample_event_1], 1, nil, Map.put(@sample_producer, "agent_id", "diff"))
      assert base != diff_producer
    end

    test "verify_digest/1 returns true for unmodified envelope and false for tampered envelope" do
      envelope = FlyClient.build_envelope([@sample_event_1], 1, nil, @sample_producer)
      assert FlyClient.verify_digest(envelope) == true

      tampered = Map.put(envelope, "digest", "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")
      assert FlyClient.verify_digest(tampered) == false

      tampered_event = update_in(envelope, ["events"], fn [ev] -> [Map.put(ev, "ocel:activity", "tampered")] end)
      assert FlyClient.verify_digest(tampered_event) == false
    end
  end

  describe "Monotonic Sequencing & Cryptographic Hash Chain Validation" do
    test "builds and validates continuous hash chain over sequential envelopes" do
      env1 = FlyClient.build_envelope([@sample_event_1], 1, nil, @sample_producer)
      env2 = FlyClient.build_envelope([@sample_event_2], 2, env1["digest"], @sample_producer)
      env3 = FlyClient.build_envelope([@sample_event_1, @sample_event_2], 3, env2["digest"], @sample_producer)

      assert {:ok, 3} = FlyClient.verify_chain([env1, env2, env3])
    end

    test "verify_chain detects broken previous_digest link" do
      env1 = FlyClient.build_envelope([@sample_event_1], 1, nil, @sample_producer)
      env2 = FlyClient.build_envelope([@sample_event_2], 2, "corrupted_prev_digest", @sample_producer)

      assert {:error, {:broken_hash_chain, _}} = FlyClient.verify_chain([env1, env2])
    end

    test "verify_chain detects non-monotonic sequence gap" do
      env1 = FlyClient.build_envelope([@sample_event_1], 1, nil, @sample_producer)
      env3 = FlyClient.build_envelope([@sample_event_2], 3, env1["digest"], @sample_producer)

      assert {:error, {:non_monotonic_sequence, %{expected: 2, actual: 3}}} = FlyClient.verify_chain([env1, env3])
    end
  end

  describe "HTTP Dispatching with Mock & Custom Dispatcher" do
    test "dispatches envelope payload to control plane URL endpoint" do
      parent = self()

      mock_dispatcher = fn url, headers, body ->
        send(parent, {:dispatched, url, headers, Jason.decode!(body)})
        {:ok, 200, Jason.encode!(%{"acknowledged" => true, "status" => "stored"})}
      end

      envelope = FlyClient.build_envelope([@sample_event_1], 1, nil, @sample_producer)

      assert {:ok, resp} =
               FlyClient.dispatch_envelope(envelope,
                 control_plane_url: "https://control-plane.fly.dev",
                 api_key: "fly_secret_token_123",
                 dispatcher: mock_dispatcher
               )

      assert resp["acknowledged"] == true

      assert_receive {:dispatched, url, headers, dispatched_envelope}
      assert url == "https://control-plane.fly.dev/api/v1/ocel/events"
      assert {"authorization", "Bearer fly_secret_token_123"} in headers
      assert {"content-type", "application/json"} in headers
      assert dispatched_envelope["schema"] == "chatgpt-cloud-ocel/1"
      assert dispatched_envelope["sequence"] == 1
    end

    test "offline fallback buffers payload to disk on HTTP network failure", %{fallback_path: fallback_path} do
      mock_failing_dispatcher = fn _url, _headers, _body ->
        {:error, :econnrefused}
      end

      envelope = FlyClient.build_envelope([@sample_event_1], 1, nil, @sample_producer)

      assert {:error, {:offline_buffered, :econnrefused}} =
               FlyClient.dispatch_envelope(envelope,
                 control_plane_url: "http://unreachable.local",
                 offline_fallback_path: fallback_path,
                 dispatcher: mock_failing_dispatcher
               )

      assert File.exists?(fallback_path)
      lines = File.read!(fallback_path) |> String.split("\n", trim: true)
      assert length(lines) == 1
      saved = Jason.decode!(List.first(lines))
      assert saved["digest"] == envelope["digest"]
    end

    test "offline fallback buffers payload on HTTP 500 error", %{fallback_path: fallback_path} do
      mock_server_error = fn _url, _headers, _body ->
        {:ok, 500, "Internal Server Error"}
      end

      envelope = FlyClient.build_envelope([@sample_event_1], 1, nil, @sample_producer)

      assert {:error, {:offline_buffered, {:http_error, 500, "Internal Server Error"}}} =
               FlyClient.dispatch_envelope(envelope,
                 control_plane_url: "http://error.local",
                 offline_fallback_path: fallback_path,
                 dispatcher: mock_server_error
               )

      assert File.exists?(fallback_path)
    end
  end

  describe "FlyClient GenServer Buffer, Batching, and Offline Replay" do
    test "buffers events and dispatches on batch_size limit", %{fallback_path: fallback_path} do
      parent = self()

      mock_dispatcher = fn url, _headers, body ->
        send(parent, {:batch_received, url, Jason.decode!(body)})
        {:ok, 200, Jason.encode!(%{"status" => "ok"})}
      end

      {:ok, client} =
        FlyClient.start_link(
          name: nil,
          batch_size: 2,
          auto_flush: false,
          offline_fallback_path: fallback_path,
          dispatcher: mock_dispatcher,
          producer: @sample_producer
        )

      # 1. First event -> buffered (buffer_count = 1)
      :ok = FlyClient.push_event(client, @sample_event_1)
      state1 = FlyClient.get_state(client)
      assert state1.buffer_count == 1
      assert state1.sequence == 0
      refute_receive {:batch_received, _, _}

      # 2. Second event -> triggers automatic batch flush (batch_size = 2)
      :ok = FlyClient.push_event(client, @sample_event_2)
      assert_receive {:batch_received, _url, env1}
      assert env1["sequence"] == 1
      assert length(env1["events"]) == 2

      state2 = FlyClient.get_state(client)
      assert state2.buffer_count == 0
      assert state2.sequence == 1
      assert state2.previous_digest == env1["digest"]

      FlyClient.stop(client)
    end

    test "manual flush creates correctly chained envelope", %{fallback_path: fallback_path} do
      parent = self()

      mock_dispatcher = fn _url, _headers, body ->
        send(parent, {:flushed, Jason.decode!(body)})
        {:ok, 200, "{}"}
      end

      {:ok, client} =
        FlyClient.start_link(
          name: nil,
          batch_size: 100,
          auto_flush: false,
          offline_fallback_path: fallback_path,
          dispatcher: mock_dispatcher,
          producer: @sample_producer
        )

      # Empty flush returns {:ok, :empty}
      assert {:ok, :empty} = FlyClient.flush(client)

      # Push events and manual flush
      :ok = FlyClient.push_events(client, [@sample_event_1, @sample_event_2])
      assert {:ok, env1} = FlyClient.flush(client)
      assert env1["sequence"] == 1
      assert env1["previous_digest"] == nil

      # Push another and flush -> verifies sequence 2 and hash chaining
      :ok = FlyClient.push_event(client, @sample_event_1)
      assert {:ok, env2} = FlyClient.flush(client)
      assert env2["sequence"] == 2
      assert env2["previous_digest"] == env1["digest"]

      assert {:ok, 2} = FlyClient.verify_chain([env1, env2])

      FlyClient.stop(client)
    end

    test "auto-flush timer flushes buffered events automatically", %{fallback_path: fallback_path} do
      parent = self()

      mock_dispatcher = fn _url, _headers, body ->
        send(parent, {:timer_flushed, Jason.decode!(body)})
        {:ok, 200, "{}"}
      end

      {:ok, client} =
        FlyClient.start_link(
          name: nil,
          batch_size: 100,
          flush_interval_ms: 50,
          auto_flush: true,
          offline_fallback_path: fallback_path,
          dispatcher: mock_dispatcher,
          producer: @sample_producer
        )

      :ok = FlyClient.push_event(client, @sample_event_1)

      assert_receive {:timer_flushed, env}, 500
      assert env["sequence"] == 1
      assert length(env["events"]) == 1

      state = FlyClient.get_state(client)
      assert state.buffer_count == 0
      assert state.sequence == 1

      FlyClient.stop(client)
    end

    test "replays offline buffered events when connectivity is restored", %{fallback_path: fallback_path} do
      # 1. Start client with failing dispatcher to simulate offline mode
      failing_dispatcher = fn _url, _headers, _body -> {:error, :nxdomain} end

      {:ok, client} =
        FlyClient.start_link(
          name: nil,
          batch_size: 10,
          auto_flush: false,
          offline_fallback_path: fallback_path,
          dispatcher: failing_dispatcher,
          producer: @sample_producer
        )

      :ok = FlyClient.push_event(client, @sample_event_1)
      assert {:ok, env1} = FlyClient.flush(client)

      state_offline = FlyClient.get_state(client)
      assert state_offline.offline_queue_count == 1
      assert File.exists?(fallback_path)

      # 2. Replay with working dispatcher
      parent = self()

      working_dispatcher = fn url, _headers, body ->
        send(parent, {:replayed, url, Jason.decode!(body)})
        {:ok, 200, "{}"}
      end

      assert {:ok, replayed_count} = FlyClient.replay_offline(client, dispatcher: working_dispatcher)
      assert replayed_count == 1

      assert_receive {:replayed, _url, replayed_env}
      assert replayed_env["digest"] == env1["digest"]

      state_recovered = FlyClient.get_state(client)
      assert state_recovered.offline_queue_count == 0
      refute File.exists?(fallback_path)

      FlyClient.stop(client)
    end
  end
end
