# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.VKG.V26928VerifyTest do
  use ExUnit.Case, async: true

  import AshR2RML.VKGCase
  alias AshR2RML.Refusal
  alias AshR2RML.VKG.{Executor, Metrics, Planner, Provenance, Receipt, Replay, Result, Serializer, Session}

  @engine AshR2RML.VKGCase.FakeEngine

  defp sealed(ids \\ ["customer", "order"], opts \\ [], plan_opts \\ []) do
    catalog = catalog(ids)
    {:ok, plan} = Planner.plan(catalog, ids, plan_opts)
    {:ok, result, observations} = Executor.execute(plan, [engine: @engine] ++ opts)
    receipt = Receipt.build(plan, result, observations)
    {plan, result, observations, receipt, Session.new(catalog, plan, result, observations, receipt)}
  end

  defp replay_refusal(subject, outcome) do
    assert {:error, %Refusal{code: :REFUSED_VKG_REPLAY, subject: ^subject}} = outcome
  end

  describe "receipt tamper through Replay" do
    test "untouched sealed session verifies everywhere" do
      {plan, result, observations, receipt, session} = sealed()
      assert :ok = Replay.verify(receipt, plan, result, observations)
      assert :ok = Session.verify(session)
      assert String.length(receipt.sha256) == 64
      assert receipt.id == "vkg-receipt-" <> binary_part(receipt.sha256, 0, 20)
    end

    test "mutated rows with stale digest are refused" do
      {plan, result, _o, receipt, _s} = sealed()
      forged = %{result | rows: [%{"subject" => "urn:evil"}]}
      replay_refusal(:result, Replay.verify(receipt, plan, forged))
    end

    test "mutated rows with row_count kept and sha recomputed by Result.build are refused" do
      {plan, result, _o, receipt, _s} = sealed(["customer"])
      rebuilt = Result.build(plan.sha256, [%{"subject" => "urn:evil"}])
      assert rebuilt.row_count == result.row_count
      replay_refusal(:result, Replay.verify(receipt, plan, rebuilt))
    end

    test "forged receipt id, contract_ids, previous, observation digest and standing are each refused" do
      {plan, result, _o, receipt, _s} = sealed()

      replay_refusal(:id, Replay.verify(%{receipt | id: "vkg-receipt-" <> String.duplicate("0", 20)}, plan, result))

      replay_refusal(
        :contract_ids,
        Replay.verify(%{receipt | contract_ids: Enum.reverse(receipt.contract_ids)}, plan, result)
      )

      replay_refusal(
        :sha256,
        Replay.verify(%{receipt | previous: "vkg-receipt-" <> String.duplicate("a", 20)}, plan, result)
      )

      replay_refusal(
        :sha256,
        Replay.verify(
          %{receipt | observation_sha256_by_contract: Map.put(receipt.observation_sha256_by_contract, "customer", "x")},
          plan,
          result
        )
      )

      replay_refusal(:standing, Replay.verify(%{receipt | standing: :live}, plan, result))
      replay_refusal(:authority, Replay.verify(%{receipt | authority: :write}, plan, result))
      replay_refusal(:row_count, Replay.verify(%{receipt | row_count: 99}, plan, result))
    end

    test "forged id that also recomputes nothing is refused even with sha256 nil" do
      {plan, result, _o, receipt, _s} = sealed()
      replay_refusal(:sha256, Replay.verify(%{receipt | sha256: nil}, plan, result))
    end

    test "tampered plan digest and mutated plan bounds are refused" do
      {plan, result, _o, receipt, _s} = sealed()
      replay_refusal(:plan, Replay.verify(receipt, %{plan | max_rows: plan.max_rows + 1}, result))
    end

    test "result built for another plan is refused even when receipt is rebuilt around it" do
      {plan, _result, observations, _receipt, _s} = sealed()
      foreign = Result.build(String.duplicate("f", 64), [])
      receipt = Receipt.build(plan, foreign, observations)
      replay_refusal(:result_plan, Replay.verify(receipt, plan, foreign))
    end

    test "receipt for different plan and catalog is refused" do
      {_plan, result, _o, receipt, _s} = sealed()
      {other_plan, _r, _o2, _r2, _s2} = sealed(["customer"])
      replay_refusal(:plan, Replay.verify(receipt, other_plan, result))
    end
  end

  describe "session tamper" do
    test "each independent mutation is refused with REFUSED_VKG_REPLAY" do
      {_plan, result, observations, receipt, session} = sealed()

      replay_refusal(:result, Session.verify(%{session | result: %{result | rows: []}}))
      replay_refusal(:result, Session.verify(%{session | result: %{result | sha256: String.duplicate("0", 64)}}))

      replay_refusal(
        :id,
        Session.verify(%{session | receipt: %{receipt | id: "vkg-receipt-" <> String.duplicate("1", 20)}})
      )

      replay_refusal(:contract_ids, Session.verify(%{session | receipt: %{receipt | contract_ids: ["customer"]}}))

      replay_refusal(
        :sha256,
        Session.verify(%{session | receipt: %{receipt | previous: "vkg-receipt-" <> String.duplicate("2", 20)}})
      )

      replay_refusal(:catalog, Session.verify(%{session | catalog_sha256: String.duplicate("9", 64)}))

      tampered_obs = put_in(observations, ["customer", Access.key(:observation_sha256)], "deadbeef")
      replay_refusal(:observations, Session.verify(%{session | observations: tampered_obs}))
    end

    test "recorded observation rows mutated with digest untouched fail reconstruction" do
      {_plan, _result, observations, _receipt, session} = sealed()
      tampered = put_in(observations, ["customer", Access.key(:rows)], [%{"subject" => "urn:x", "name" => "Evil"}])
      # the executor re-derives each recorded observation digest from its rows, so the
      # forgery is refused at the stage before result reconstruction is even compared
      assert {:error, %Refusal{code: :REFUSED_VKG_REPLAY, detail: detail}} =
               Session.verify(%{session | observations: tampered})

      assert detail =~ "recorded observation digest does not derive"
    end

    test "metrics and inspection report tamper" do
      {_plan, result, _o, _r, session} = sealed()
      bad = %{session | result: %{result | rows: []}}
      assert Metrics.from_session(session).replay_verifiable?
      refute Metrics.from_session(bad).replay_verifiable?
      assert {:error, %Refusal{code: :REFUSED_VKG_REPLAY}} = AshR2RML.VKG.Inspection.session(bad).replay
      assert :ok = AshR2RML.VKG.Inspection.session(session).replay
    end

    test "summary reports ids and standing" do
      {plan, _r, _o, receipt, session} = sealed()
      summary = Session.summary(session)
      assert summary.receipt_id == receipt.id
      assert summary.plan_id == plan.id
      assert summary.standing == :test_double_only
    end
  end

  describe "chain" do
    test "valid two-link chain, head must be nil, skipped links rejected" do
      {plan, result, observations, first, _s} = sealed()
      second = Receipt.build(plan, result, observations, first)
      third = Receipt.build(plan, result, observations, second.id)

      assert second.previous == first.id
      assert Receipt.chain_valid?([first, second, third])
      refute Receipt.chain_valid?([first, third])
      refute Receipt.chain_valid?([second, third])
      assert Receipt.chain_valid?([second, third], anchor: first.id)
      refute Receipt.chain_valid?([second, third], anchor: third.id)
    end

    test "headless, wrong-previous single, forged id and non-receipt entries are rejected" do
      {plan, result, observations, first, _s} = sealed()
      wrong = Receipt.build(plan, result, observations, "wrong")
      refute Receipt.chain_valid?([wrong])
      refute Receipt.chain_valid?([%{first | id: "vkg-receipt-" <> String.duplicate("3", 20)}])
      refute Receipt.chain_valid?([first, :nope])
      assert Receipt.chain_valid?([])
      assert Receipt.chain_valid?([first])
    end

    test "chain rejects a link whose previous was rewritten to fit" do
      {plan, result, observations, first, _s} = sealed()
      second = Receipt.build(plan, result, observations, first.id)
      refute Receipt.chain_valid?([first, %{second | previous: nil}])
    end
  end

  describe "Replay.reconstruct" do
    test "round-trips a live union session result" do
      {plan, result, observations, _r, _s} = sealed()
      assert {:ok, rebuilt} = Replay.reconstruct(plan, observations)
      assert rebuilt.sha256 == result.sha256
      assert Result.equivalent?(rebuilt, result)
    end

    test "round-trips by_subject merge" do
      rows = %{
        "customer" => [%{"subject" => "urn:s1", "name" => "A"}],
        "order" => [%{"subject" => "urn:s1", "total" => 5}]
      }

      {plan, result, observations, _r, _s} = sealed(["customer", "order"], [fake_rows: rows], merge: :by_subject)
      assert plan.merge == :by_subject
      assert result.row_count == 1
      assert {:ok, rebuilt} = Replay.reconstruct(plan, observations)
      assert rebuilt.sha256 == result.sha256
    end

    test "union dedupes identical rows and reconstruct agrees" do
      row = %{"subject" => "urn:same", "name" => "X"}
      rows = %{"customer" => [row, row]}
      {plan, result, observations, _r, _s} = sealed(["customer"], fake_rows: rows)
      assert result.row_count == 1
      assert {:ok, %Result{row_count: 1}} = Replay.reconstruct(plan, observations)
    end

    test "refuses extra, missing and malformed observations with typed refusals" do
      {plan, _result, observations, _r, _s} = sealed()
      extra = Map.put(observations, "ghost", observations["customer"])

      assert {:error, %Refusal{code: :REFUSED_VKG_REPLAY, subject: :contract_ids, evidence: %{extra: ["ghost"]}}} =
               Replay.reconstruct(plan, extra)

      assert {:error, %Refusal{code: :REFUSED_VKG_REPLAY, subject: :contract_ids, evidence: %{missing: ["order"]}}} =
               Replay.reconstruct(plan, Map.delete(observations, "order"))

      assert {:error, %Refusal{code: :REFUSED_VKG_REPLAY, subject: :observations}} =
               Replay.reconstruct(plan, Map.put(observations, "order", %{}))

      assert {:error, %Refusal{code: :REFUSED_VKG_REPLAY}} = Replay.reconstruct(plan, :nope)
    end

    test "refuses a tampered plan and enforces the row bound" do
      {plan, _result, observations, _r, _s} = sealed()
      assert {:error, %Refusal{code: :REFUSED_VKG_REPLAY}} = Replay.reconstruct(%{plan | max_rows: 1}, observations)
    end

    test "compare refuses differing sha and forged row count" do
      {_plan, result, _o, receipt, _s} = sealed()

      assert {:error, %Refusal{code: :REFUSED_VKG_REPLAY, evidence: %{expected_sha256: _, observed_sha256: _}}} =
               Replay.compare(receipt, %{result | sha256: "0"})

      assert {:error, %Refusal{code: :REFUSED_VKG_REPLAY}} = Replay.compare(%{receipt | row_count: 42}, result)
    end
  end

  describe "canonical serializer" do
    test "nil, booleans and numbers survive; first receipt previous is JSON null" do
      {_plan, _result, _o, receipt, _s} = sealed()
      decoded = receipt |> Serializer.encode_receipt!() |> Jason.decode!()
      assert decoded["previous"] == nil
      assert decoded["sha256"] == receipt.sha256

      json =
        Serializer.canonical_json(%{"a" => nil, "b" => true, "c" => false, "d" => 1, "e" => 1.5, "f" => "nil", g: :sym})

      assert Jason.decode!(json) == %{
               "a" => nil,
               "b" => true,
               "c" => false,
               "d" => 1,
               "e" => 1.5,
               "f" => "nil",
               "g" => %{"$atom" => "sym"}
             }

      # an atom, a string and nil-like atoms never share an encoding
      refute Serializer.canonical_json(:sym) == Serializer.canonical_json("sym")
    end

    test "boolean and nil row values survive session encoding without colliding with strings" do
      rows = %{"customer" => [%{"subject" => "urn:s", "flag" => false, "gone" => nil, "text" => "false"}]}
      {_plan, _result, _o, _r, session} = sealed(["customer"], fake_rows: rows)
      [row] = session |> Serializer.encode_session!() |> Jason.decode!() |> get_in(["result", "rows"])
      assert row["flag"] === false
      assert row["gone"] === nil
      assert row["text"] == "false"
    end

    test "key order is deterministic and independent of map construction; structs and tuples are total" do
      big = for i <- 1..60, into: %{}, do: {"k#{i}", i}

      assert Serializer.canonical_json(big) ==
               Serializer.canonical_json(big |> Map.to_list() |> Enum.reverse() |> Map.new())

      json =
        Serializer.canonical_json(%{
          "t" => {1, 2},
          "l" => [1, 2],
          "d" => ~U[2026-09-28 00:00:00Z],
          "bin" => <<255, 254>>
        })

      decoded = Jason.decode!(json)
      assert decoded["t"] == %{"$tuple" => [1, 2]}
      assert decoded["l"] == [1, 2]
      assert decoded["d"] == %{"$datetime" => "2026-09-28T00:00:00Z"}
      assert Map.has_key?(decoded["bin"], "$binary")
      refute Serializer.digest({1, 2}) == Serializer.digest([1, 2])
    end

    test "session JSON is byte-identical across independent runs" do
      {_, _, _, _, a} = sealed()
      {_, _, _, _, b} = sealed()
      assert Serializer.encode_session!(a) == Serializer.encode_session!(b)
    end

    test "decoded receipt and result verify; tampered JSON does not" do
      {plan, result, _o, receipt, _s} = sealed()
      rjson = Serializer.encode_receipt!(receipt)
      resjson = Serializer.encode_result!(result)

      assert {:ok, decoded} = Serializer.decode_receipt(rjson)
      assert decoded == receipt
      assert {:ok, decoded_result} = Serializer.decode_result(resjson)
      assert :ok = Result.verify(decoded_result)
      assert :ok = Serializer.verify_receipt_json(rjson, resjson, plan)

      forged = rjson |> Jason.decode!() |> Map.put("row_count", 7) |> Jason.encode!()
      assert {:error, %Refusal{code: :REFUSED_VKG_REPLAY}} = Serializer.verify_receipt_json(forged, resjson, plan)

      bad_rows = resjson |> Jason.decode!() |> Map.put("rows", []) |> Jason.encode!()
      assert {:error, %Refusal{code: :REFUSED_VKG_REPLAY}} = Serializer.verify_receipt_json(rjson, bad_rows, plan)

      assert {:error, %Refusal{code: :REFUSED_VKG_REPLAY}} = Serializer.decode_receipt("not json")
      auth = rjson |> Jason.decode!() |> Map.put("authority", "write") |> Jason.encode!()
      assert {:error, %Refusal{code: :REFUSED_VKG_REPLAY}} = Serializer.decode_receipt(auth)
    end
  end

  describe "identity normalization" do
    test "row digest is invariant under atom vs string keys and map order" do
      {_c, plan} = plan(["customer"])
      [stage] = plan.stages
      obs = %{observation_sha256: "o"}
      a = Provenance.attach(%{"subject" => "urn:s", "name" => "x"}, stage, obs)
      b = Provenance.attach(%{"subject" => "urn:s", name: "x"}, stage, obs)
      assert a["_vkg"]["row_sha256"] == b["_vkg"]["row_sha256"]
      assert String.length(a["_vkg"]["row_sha256"]) == 64
      c = Provenance.attach(%{"subject" => "urn:s", "name" => {"x"}}, stage, obs)
      refute a["_vkg"]["row_sha256"] == c["_vkg"]["row_sha256"]
    end

    test "Result digest is permutation and key-type invariant; colliding keys resolve to the string key" do
      {_c, plan} = plan(["customer"])
      r1 = Result.build(plan.sha256, [%{"a" => 1}, %{"b" => 2}])
      r2 = Result.build(plan.sha256, [%{b: 2}, %{a: 1}])
      assert r1.sha256 == r2.sha256

      collided = Result.build(plan.sha256, [%{:a => 1, "a" => 2}])
      assert collided.rows == [%{"a" => 2}]
      assert :ok = Result.verify(r1)
      assert {:error, %Refusal{subject: :row_count}} = Result.verify(%{r1 | row_count: 5})
      assert {:error, %Refusal{subject: :sources}} = Result.verify(%{r1 | sources: %{"x" => 1}})
    end

    test "Receipt.build is idempotent and sensitive to previous" do
      {plan, result, observations, first, _s} = sealed()
      assert first == Receipt.build(plan, result, observations)
      refute first.sha256 == Receipt.build(plan, result, observations, first).sha256
    end
  end
end
