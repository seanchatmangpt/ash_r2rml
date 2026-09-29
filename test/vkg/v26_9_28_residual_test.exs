# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.VKG.V26928ResidualTest do
  use ExUnit.Case, async: true

  import AshR2RML.VKGCase

  alias AshR2RML.Refusal

  alias AshR2RML.VKG.{
    Batch,
    Catalog,
    Executor,
    Inspection,
    Planner,
    QueryPlan,
    Receipt,
    Replay,
    Result,
    Serializer,
    Session
  }

  alias AshR2RML.VKG.Consumer.Engineering

  @fake AshR2RML.VKGCase.FakeEngine
  @root Path.expand("../..", __DIR__)

  defmodule SwapEngine do
    # Swaps the admitted files on disk while the engine is running, then reads the
    # inputs the executor handed it before and after the swap.
    def execute(stage, opts) do
      before = File.read!(stage.mapping_path)
      File.write!(Keyword.fetch!(opts, :swap_path), "EVIL BYTES")
      File.write!(Keyword.fetch!(opts, :swap_query_path), "EVIL QUERY")
      after_ = File.read!(stage.mapping_path)
      query = File.read!(stage.query_path)

      ontology = if stage.ontology_path, do: File.read!(stage.ontology_path)

      send(
        Keyword.fetch!(opts, :test_pid),
        {:seen, stage.mapping_path, stage.query_path, stage.ontology_path, before, after_, query, ontology}
      )

      AshR2RML.VKGCase.FakeEngine.execute(
        stage,
        Keyword.put(opts, :fake_rows, %{stage.contract_id => [%{"subject" => "urn:s", "before" => before}]})
      )
    end
  end

  defmodule CapabilityProbe do
    def execute(stage, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:required, Keyword.get(opts, :required_capabilities)})
      AshR2RML.VKGCase.FakeEngine.execute(stage, opts)
    end
  end

  defp sha(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

  # A contract whose mapping/query/ontology are real files with real digests.
  defp real_contract(dir, id \\ "customer", ontology? \\ true) do
    mapping = Path.join(dir, id <> ".r2rml.ttl")
    query = Path.join(dir, id <> ".rq")
    ontology = Path.join(dir, id <> ".onto.ttl")
    File.write!(mapping, "# mapping #{id}\n")
    File.write!(query, "SELECT * WHERE { ?s ?p ?o }\n")
    File.write!(ontology, "# ontology #{id}\n")
    base = contract(id)

    contract = %{
      base
      | mapping_path: mapping,
        mapping_sha256: sha("# mapping #{id}\n"),
        query_path: query,
        query_sha256: sha("SELECT * WHERE { ?s ?p ?o }\n")
    }

    if ontology?,
      do: %{contract | ontology_path: ontology, ontology_sha256: sha("# ontology #{id}\n")},
      else: contract
  end

  defp real_plan(dir, opts \\ []) do
    {:ok, catalog} = Catalog.new([real_contract(dir)])
    {:ok, plan} = Planner.plan(catalog, ["customer"], opts)
    {catalog, plan}
  end

  describe "1. TOCTOU: the engine only sees the hashed bytes" do
    @describetag :tmp_dir

    test "files swapped mid-run never reach the engine; snapshot is private and cleaned up", %{tmp_dir: dir} do
      {_catalog, plan} = real_plan(dir)
      [stage] = plan.stages

      assert {:ok, result, _} =
               Executor.execute(plan,
                 engine: SwapEngine,
                 verify_files: true,
                 swap_path: stage.mapping_path,
                 swap_query_path: stage.query_path,
                 test_pid: self()
               )

      assert_received {:seen, mapping, query, ontology, before, after_, query_bytes, ontology_bytes}
      assert before == "# mapping customer\n"
      assert after_ == before
      assert query_bytes == "SELECT * WHERE { ?s ?p ?o }\n"
      assert ontology_bytes == "# ontology customer\n"

      for {snapshot, original} <- [
            {mapping, stage.mapping_path},
            {query, stage.query_path},
            {ontology, stage.ontology_path}
          ] do
        refute snapshot == original
        assert Path.basename(Path.dirname(snapshot)) =~ "ash_r2rml_vkg_"
        refute File.exists?(snapshot), "snapshot must be removed after the run"
      end

      # the on-disk originals were swapped, and the result still carries admitted bytes
      assert File.read!(stage.mapping_path) == "EVIL BYTES"
      assert [%{"before" => "# mapping customer\n"}] = result.rows |> Enum.map(&Map.take(&1, ["before"]))
    end

    test "a swapped file is refused before the engine runs (mapping, query and ontology)", %{tmp_dir: dir} do
      for {field, path_key} <- [
            {:mapping_sha256, :mapping_path},
            {:query_sha256, :query_path},
            {:ontology_sha256, :ontology_path}
          ] do
        {_catalog, plan} = real_plan(dir)
        [stage] = plan.stages
        File.write!(Map.fetch!(stage, path_key), "tampered #{field}")

        assert {:error, %Refusal{code: :REFUSED_VKG_SOURCE_DRIFT} = r} =
                 Executor.execute(plan, engine: SwapEngine, verify_files: true, test_pid: self())

        assert field in r.evidence.fields
        refute_received {:seen, _, _, _, _, _, _, _}
        {_catalog, _plan} = real_plan(dir)
      end
    end

    test "the Ontop runner receives snapshot paths, including -t, and admitted bytes", %{tmp_dir: dir} do
      {_catalog, plan} = real_plan(dir)
      [stage] = plan.stages
      test_pid = self()

      runner = fn _binary, args, _opts ->
        [_query, "-m", mapping, "-q", query | rest] = args
        File.write!(stage.mapping_path, "EVIL")
        File.write!(stage.ontology_path, "EVIL")
        ["-t", ontology] = rest
        send(test_pid, {:runner, mapping, query, ontology, File.read!(mapping), File.read!(ontology)})
        {"subject,name\nhttp://x/1,A\n", 0}
      end

      assert {:ok, result, obs} = Executor.execute(plan, runner: runner, verify_files: true)
      assert result.standing == :test_double_only
      assert_received {:runner, mapping, query, ontology, mapping_bytes, ontology_bytes}
      assert mapping_bytes == "# mapping customer\n"
      assert ontology_bytes == "# ontology customer\n"
      refute mapping == stage.mapping_path
      assert Path.dirname(mapping) == Path.dirname(query)
      assert Path.dirname(mapping) == Path.dirname(ontology)
      refute File.exists?(mapping)
      assert obs["customer"].mapping_sha256 == stage.mapping_sha256
    end

    test "a live process run sees the snapshot and still earns live standing", %{tmp_dir: dir} do
      bin = Path.join(dir, "fakeontop")
      File.write!(bin, "#!/bin/sh\nprintf 'subject,mapping_path\\nhttp://x/1,%s\\n' \"$3\"\n")
      File.chmod!(bin, 0o755)
      {_catalog, plan} = real_plan(dir)
      [stage] = plan.stages

      assert {:ok, result, obs} = Executor.execute(plan, binary: bin)
      assert result.standing == :observed_not_actuated
      assert obs["customer"].evidence_kind == :system_process
      [row] = result.rows
      assert row["mapping_path"] =~ "ash_r2rml_vkg_"
      refute row["mapping_path"] == stage.mapping_path
      refute File.exists?(row["mapping_path"])
    end

    test "engine exceptions still clean the snapshot", %{tmp_dir: dir} do
      {_catalog, plan} = real_plan(dir)
      test_pid = self()

      runner = fn _b, args, _o ->
        send(test_pid, {:path, Enum.at(args, 2)})
        raise "boom"
      end

      assert {:error, %Refusal{}} = Executor.execute(plan, runner: runner, verify_files: true)
      assert_received {:path, path}
      refute File.exists?(path)
    end
  end

  describe "2. hand-built plans are bound to a catalog" do
    @describetag :tmp_dir

    test "a plan without catalog binding is refused; VKG.query still works" do
      {catalog, plan} = plan(["customer"])
      {:ok, hand} = QueryPlan.new(plan.catalog_sha256, plan.contract_ids, plan.stages)
      assert hand.sha256 == plan.sha256
      assert is_nil(hand.catalog)

      assert {:error, %Refusal{code: :REFUSED_VKG_QUERY_PLAN, subject: :catalog}} =
               Executor.execute(hand, engine: @fake)

      assert {:ok, _, _} = Executor.execute(hand, engine: @fake, catalog: catalog)
      assert {:ok, _, _} = Executor.execute(plan, engine: @fake)

      assert {:ok, session} = AshR2RML.VKG.query(["customer"], engine: @fake)
      assert :ok = AshR2RML.VKG.verify(session)
      assert session.plan.catalog.sha256 == session.plan.catalog_sha256
    end

    test "arbitrary paths on a hand-built plan are refused (paths are not in the digest)", %{tmp_dir: dir} do
      {catalog, plan} = real_plan(dir)
      evil = Enum.map(plan.stages, &%{&1 | mapping_path: "/etc/passwd", query_path: "/etc/shadow"})
      {:ok, hand} = QueryPlan.new(plan.catalog_sha256, plan.contract_ids, evil, catalog: catalog)
      assert hand.sha256 == plan.sha256

      assert {:error, %Refusal{code: :REFUSED_VKG_QUERY_PLAN} = r} =
               Executor.execute(hand, engine: @fake, verify_files: true)

      assert :mapping_path in r.evidence.fields
      assert :query_path in r.evidence.fields
      assert {:error, %Refusal{code: :REFUSED_VKG_QUERY_PLAN}} = Executor.execute(hand, engine: @fake)
    end

    test "arbitrary digests on a hand-built plan are drift", %{tmp_dir: dir} do
      {catalog, plan} = real_plan(dir)
      File.write!(Path.join(dir, "evil.ttl"), "evil")

      for {field, value} <- [
            mapping_sha256: sha("evil"),
            query_sha256: sha("evil"),
            ontology_sha256: sha("evil"),
            source_sha256: sha("evil"),
            contract_digest: sha("evil")
          ] do
        stages = Enum.map(plan.stages, &Map.put(&1, field, value))
        {:ok, hand} = QueryPlan.new(plan.catalog_sha256, plan.contract_ids, stages, catalog: catalog)

        assert {:error, %Refusal{code: :REFUSED_VKG_SOURCE_DRIFT} = r} = Executor.execute(hand, engine: @fake)
        assert field in r.evidence.fields
      end
    end

    test "a different or forged catalog cannot vouch for a plan", %{tmp_dir: dir} do
      {catalog, plan} = real_plan(dir)
      other = catalog(["customer", "order"])

      assert {:error, %Refusal{code: :REFUSED_VKG_QUERY_PLAN, subject: :catalog}} =
               Executor.execute(plan, engine: @fake, catalog: other)

      forged = %{catalog | contracts: other.contracts}

      assert {:error, %Refusal{code: :REFUSED_VKG_QUERY_PLAN, subject: :catalog}} =
               Executor.execute(plan, engine: @fake, catalog: forged)

      assert {:error, %Refusal{code: :REFUSED_VKG_QUERY_PLAN, subject: :catalog}} =
               Executor.execute(plan, engine: @fake, catalog: :nope)
    end

    test "non-keyword options and non-plans are typed refusals" do
      {_c, plan} = plan(["customer"])
      assert {:error, %Refusal{code: :REFUSED_VKG_QUERY_PLAN}} = Executor.execute(plan, [1, 2])
      assert {:error, %Refusal{code: :REFUSED_VKG_QUERY_PLAN}} = Executor.execute(plan, :nope)
      assert {:error, %Refusal{code: :REFUSED_VKG_QUERY_PLAN}} = Executor.execute(%{plan | id: "x"}, engine: @fake)
      assert {:error, %Refusal{code: :REFUSED_VKG_QUERY_PLAN}} = Executor.execute(:not_a_plan, [])
    end
  end

  describe "3. capability and ontology forwarding" do
    @describetag :tmp_dir

    test "the requested capability reaches the engine and the Ontop capability receipt" do
      for capability <- [:select, :filter, :join] do
        {_c, plan} = plan_with(capability)
        assert {:ok, _, _} = Executor.execute(plan, engine: CapabilityProbe, test_pid: self())
        assert_received {:required, [^capability]}
      end

      {_c, plan} = plan_with(:join)
      runner = fn _b, _a, _o -> {"subject,name\nhttp://x/1,A\n", 0} end
      assert {:ok, _, obs} = Executor.execute(plan, runner: runner, verify_files: false)
      assert obs["customer"].capability_receipt.required == [:join]
      assert obs["customer"].capability_receipt.executed?
    end

    test "an engine that does not admit a required capability refuses the stage" do
      {_c, plan} = plan_with(:select)
      runner = fn _b, _a, _o -> {"subject,name\nhttp://x/1,A\n", 0} end

      assert {:error, %Refusal{code: :REFUSED_VKG_EXECUTION} = r} =
               Executor.execute(plan, runner: runner, verify_files: false, required_capabilities: [:definitely_not])

      assert r.evidence.cause.code == :REFUSED_OBDA_CAPABILITY
    end

    test "every stage must carry ontology_sha256 or none does", %{tmp_dir: dir} do
      {:ok, mixed} = Catalog.new([real_contract(dir, "customer"), real_contract(dir, "order", false)])

      # the planner refuses the mixed selection outright
      assert {:error, %Refusal{code: :REFUSED_VKG_QUERY_PLAN, subject: :ontology_sha256}} =
               Planner.plan(mixed, ["customer", "order"])

      stages =
        Enum.map(["customer", "order"], fn id ->
          id |> then(&Catalog.fetch(mixed, &1)) |> elem(1) |> Planner.stage_for()
        end)

      assert {:error, %Refusal{code: :REFUSED_VKG_QUERY_PLAN, subject: :ontology_sha256}} =
               QueryPlan.new(mixed.sha256, ["customer", "order"], stages)

      # a valid two-stage plan whose second stage is later stripped of its ontology
      {:ok, both} = Catalog.new([real_contract(dir, "customer"), real_contract(dir, "order")])
      {:ok, plan} = Planner.plan(both, ["customer", "order"])
      assert plan.ontology_sha256 != nil
      stripped = %{plan | stages: [hd(plan.stages), %{List.last(plan.stages) | ontology_sha256: nil}]}

      assert {:error, %Refusal{code: :REFUSED_VKG_QUERY_PLAN, subject: :ontology_sha256}} = QueryPlan.verify(stripped)

      assert {:error, %Refusal{code: :REFUSED_VKG_QUERY_PLAN, subject: :ontology_sha256}} =
               Executor.execute(stripped, engine: @fake)

      {_c, good} = real_plan(dir)
      no_digest = Enum.map(good.stages, &Map.put(&1, :ontology_sha256, nil))

      assert {:error, %Refusal{code: :REFUSED_VKG_QUERY_PLAN, subject: :ontology_sha256}} =
               QueryPlan.new(good.catalog_sha256, good.contract_ids, no_digest)

      forged_binding = %{good | ontology_sha256: String.duplicate("0", 64)}
      assert {:error, %Refusal{code: :REFUSED_VKG_QUERY_PLAN}} = QueryPlan.verify(forged_binding)
    end

    defp plan_with(capability) do
      {:ok, catalog} = Catalog.new([contract("customer")])
      {:ok, plan} = Planner.plan(catalog, ["customer"], capability: capability)
      {catalog, plan}
    end
  end

  describe "4. injective canonical encoding replaces term_to_binary" do
    test "plan and executor sources no longer hash BEAM external terms" do
      for file <- ["query_plan.ex", "executor.ex"] do
        source = File.read!(Path.join(@root, "lib/ash_r2rml/vkg/" <> file))
        refute source =~ "term_to_binary", "#{file} must use the canonical JSON digest"
      end
    end

    test "type-swapped values never share an encoding" do
      distinct = [
        :sym,
        "sym",
        %{"$atom" => "sym"},
        {1, 2},
        [1, 2],
        %{"$tuple" => [1, 2]},
        ~D[2026-09-28],
        "2026-09-28",
        %{"$date" => "2026-09-28"},
        Decimal.new("1.5"),
        "1.5",
        1.5,
        ~T[10:00:00],
        ~N[2026-09-28 10:00:00],
        ~U[2026-09-28 10:00:00Z],
        <<255>>,
        %{"$binary" => "/w=="},
        %{1 => "x"},
        %{"1" => "x"},
        %{"a" => 2, a: 1},
        %{"a" => 2},
        %{"$pairs" => []},
        1,
        "1",
        nil,
        "nil",
        true,
        "true"
      ]

      encoded = Enum.map(distinct, &Serializer.canonical_json/1)
      assert length(Enum.uniq(encoded)) == length(distinct)
      assert length(Enum.uniq(Enum.map(distinct, &Serializer.digest/1))) == length(distinct)
    end

    test "colliding and non-string keys never drop a member" do
      json = Serializer.canonical_json(%{:a => 1, "a" => 2})
      assert json =~ "$pairs"
      assert json =~ "1" and json =~ "2"
    end

    test "tagged values survive a JSON round trip through decode_value" do
      values = [
        :ok,
        ~D[2026-09-28],
        ~T[10:00:00],
        ~N[2026-09-28 10:00:00],
        ~U[2026-09-28 10:00:00Z],
        Decimal.new("1.50"),
        {1, [2, {3}]},
        <<255, 254>>,
        %{"$atom" => "user data"},
        %{"nested" => [%{"t" => {:ok, "x"}}]}
      ]

      for value <- values do
        json = Serializer.canonical_json(value)
        assert json |> Jason.decode!() |> Serializer.decode_value() == value
        assert json |> Jason.decode!() |> Serializer.decode_value() |> Serializer.canonical_json() == json
      end

      # untrusted JSON cannot mint atoms
      bogus = %{"$atom" => "definitely_not_an_existing_atom_#{System.unique_integer([:positive])}"}
      assert Serializer.decode_value(bogus) == bogus
    end

    test "observation digests distinguish types that term_to_binary-after-flattening collapsed" do
      digest = fn value ->
        rows = %{"customer" => [%{"subject" => "urn:s", "v" => value}]}
        {_c, plan} = plan(["customer"])
        {:ok, result, obs} = Executor.execute(plan, engine: @fake, fake_rows: rows)
        {result, obs["customer"].observation_sha256}
      end

      cases = [{1, 2}, [1, 2], :active, "active", ~D[2026-09-28], "2026-09-28", Decimal.new("1.5"), "1.5"]
      digests = Enum.map(cases, fn value -> value |> digest.() |> elem(1) end)
      assert length(Enum.uniq(digests)) == length(cases)

      {r_tuple, _} = digest.({1, 2})
      {r_list, _} = digest.([1, 2])
      # the sealed result projects both to the same JSON-native list ...
      assert hd(r_tuple.rows)["v"] == hd(r_list.rows)["v"]

      # ... but the receipt still binds the distinct observation digests
      {c, plan} = plan(["customer"])

      receipts =
        for value <- [{1, 2}, [1, 2]] do
          rows = %{"customer" => [%{"subject" => "urn:s", "v" => value}]}
          {:ok, result, obs} = Executor.execute(plan, engine: @fake, fake_rows: rows)
          _ = c
          Receipt.build(plan, result, obs)
        end

      assert length(Enum.uniq_by(receipts, & &1.sha256)) == 2
    end

    test "observation digest is invariant under engine row order and key order" do
      {_c, plan} = plan(["customer"])
      a = [%{"subject" => "1", "n" => "a"}, %{"subject" => "2", "n" => "b"}]
      b = [%{n: "b", subject: "2"}, %{"n" => "a", "subject" => "1"}]

      digests =
        for rows <- [a, b] do
          {:ok, _r, obs} = Executor.execute(plan, engine: @fake, fake_rows: %{"customer" => rows})
          obs["customer"].observation_sha256
        end

      assert [same, same] = digests
    end
  end

  describe "5. decode_receipt accepts every emittable standing" do
    @describetag :tmp_dir

    test "standings come from one source of truth and all round trip" do
      assert Enum.sort(Result.standings()) == [:observed_not_actuated, :test_double_only]
      {_c, plan} = plan(["customer"])
      {:ok, result, obs} = Executor.execute(plan, engine: @fake)

      for standing <- Result.standings() do
        sealed = Result.build(plan.sha256, result.rows, standing)
        receipt = Receipt.build(plan, sealed, obs)
        assert receipt.standing == standing
        assert {:ok, ^receipt} = receipt |> Serializer.encode_receipt!() |> Serializer.decode_receipt()
        assert {:ok, ^sealed} = sealed |> Serializer.encode_result!() |> Serializer.decode_result()
      end
    end

    test "a live executor run emits a standing the decoder accepts", %{tmp_dir: dir} do
      bin = Path.join(dir, "fakeontop")
      File.write!(bin, "#!/bin/sh\nprintf 'subject,name\\nhttp://x/1,A\\n'\n")
      File.chmod!(bin, 0o755)
      {_c, plan} = plan(["customer"])
      {:ok, result, obs} = Executor.execute(plan, binary: bin, verify_files: false)
      assert result.standing in Result.standings()
      receipt = Receipt.build(plan, result, obs)
      assert {:ok, ^receipt} = receipt |> Serializer.encode_receipt!() |> Serializer.decode_receipt()
    end

    test "an unknown receipt standing is refused by integrity and decode" do
      {plan, result, obs, receipt} = sealed_double()
      forged = %{receipt | standing: :made_up}
      assert {:error, %Refusal{subject: :standing}} = Receipt.verify_integrity(forged)
      assert {:error, %Refusal{code: :REFUSED_VKG_REPLAY}} = Replay.verify(forged, plan, result, obs)

      json = receipt |> Serializer.encode_receipt!() |> String.replace("test_double_only", "made_up")
      assert {:error, %Refusal{code: :REFUSED_VKG_REPLAY}} = Serializer.decode_receipt(json)
    end
  end

  describe "6. docs closure does not depend on the source layout of the Refusal type" do
    test "codes are read through Code.Typespec" do
      codes = AshR2RML.VKGCase.refusal_codes()
      assert length(codes) > 20
      assert "REFUSED_VKG_REPLAY" in codes
      assert "REFUSED_VKG_SOURCE_DRIFT" in codes
      assert "REFUSED_RESOURCE_BOUND" in codes
    end

    test "the reader handles any layout of a union type" do
      sources = [
        "defmodule R1 do\n  @type code :: :A_ONE | :B_TWO\nend",
        "defmodule R2 do\n  @type code ::\n          :A_ONE\n          | :B_TWO\n  @type other :: :NOT_ME\nend",
        "defmodule R3 do\n  @typedoc \"docs\"\n  @type code :: :A_ONE |\n    :B_TWO\n\n\n  def f, do: 1\nend"
      ]

      for source <- sources do
        [{_module, beam}] = compile_with_debug_info(source)
        assert AshR2RML.VKGCase.type_atoms(beam, :code) == ["A_ONE", "B_TWO"]
      end
    end
  end

  describe "7. optional receipt signing (shared-key MAC)" do
    @key "0123456789abcdef-shared-key"

    test "sign / verify round trip; unsigned stays allowed unless required" do
      {plan, result, obs, receipt} = sealed_double()
      assert {:ok, signed} = Receipt.sign(receipt, @key)
      assert Receipt.signed?(signed)
      refute Receipt.signed?(receipt)
      assert signed.sha256 == receipt.sha256 and signed.id == receipt.id
      assert signed.signature =~ ~r/\Ahmac-sha256:[0-9a-f]{64}\z/

      assert :ok = Receipt.verify(signed, plan, result, obs, key: @key)
      assert :ok = Receipt.verify(signed, plan, result, obs, key: @key, require_signature: true)
      assert :ok = Replay.verify(signed, plan, result, obs, key: @key)

      assert :ok = Receipt.verify(receipt, plan, result, obs)
      assert :ok = Receipt.verify(receipt, plan, result, obs, key: @key)

      assert {:error, %Refusal{code: :REFUSED_VKG_REPLAY, subject: :signature}} =
               Receipt.verify(receipt, plan, result, obs, key: @key, require_signature: true)

      assert {:error, %Refusal{code: :REFUSED_VKG_REPLAY, subject: :signature}} =
               Receipt.verify(signed, plan, result, obs, require_signature: true)
    end

    test "wrong key, edited receipt and stripped signature are refused" do
      {plan, result, obs, receipt} = sealed_double()
      {:ok, signed} = Receipt.sign(receipt, @key)

      assert {:error, %Refusal{code: :REFUSED_VKG_REPLAY, subject: :signature}} =
               Receipt.verify(signed, plan, result, obs, key: "another-16-byte-key!")

      # attacker edits the receipt and re-seals its digest/id but cannot re-sign
      edited = %{signed | previous: "vkg-receipt-" <> String.duplicate("a", 20)}
      resealed = %{edited | sha256: Receipt.compute_sha256(edited)}
      resealed = %{resealed | id: "vkg-receipt-" <> binary_part(resealed.sha256, 0, 20)}
      assert :ok = Receipt.verify_integrity(resealed)

      assert {:error, %Refusal{code: :REFUSED_VKG_REPLAY, subject: :signature}} =
               Receipt.verify_integrity(resealed, key: @key)

      assert {:error, %Refusal{subject: :signature}} =
               Receipt.verify(%{signed | signature: 42}, plan, result, obs, key: @key)

      assert {:error, %Refusal{subject: :signature}} =
               Receipt.verify(%{signed | signature: "hmac-sha256:" <> String.duplicate("0", 64)}, plan, result, obs,
                 key: @key
               )

      stripped = %{signed | signature: nil}
      assert :ok = Receipt.verify(stripped, plan, result, obs, key: @key)

      assert {:error, %Refusal{subject: :signature}} =
               Receipt.verify(stripped, plan, result, obs, key: @key, require_signature: true)
    end

    test "weak keys and require_signature without a key are refused" do
      {plan, result, obs, receipt} = sealed_double()
      assert {:error, %Refusal{code: :REFUSED_VKG_REPLAY, subject: :key}} = Receipt.sign(receipt, "short")
      assert {:error, %Refusal{subject: :key}} = Receipt.sign(receipt, nil)
      assert {:error, %Refusal{subject: :receipt}} = Receipt.sign(:nope, @key)
      assert {:error, %Refusal{subject: :key}} = Receipt.verify(receipt, plan, result, obs, key: "short")

      assert {:error, %Refusal{subject: :signature}} =
               Receipt.verify(receipt, plan, result, obs, require_signature: true)

      forged = %{receipt | sha256: String.duplicate("0", 64)}
      assert {:error, %Refusal{code: :REFUSED_VKG_REPLAY}} = Receipt.sign(forged, @key)
    end

    test "tampering with a signed chain is refused" do
      {plan, result, obs, r1} = sealed_double()
      r2 = Receipt.build(plan, result, obs, r1)
      r3 = Receipt.build(plan, result, obs, r2)
      {:ok, [s1, s2, s3]} = sign_all([r1, r2, r3])

      assert Receipt.chain_valid?([s1, s2, s3])
      assert Receipt.chain_valid?([s1, s2, s3], key: @key, require_signature: true)
      refute Receipt.chain_valid?([s1, s2, s3], key: "another-16-byte-key!")

      # unsigned middle link inserted by an attacker
      refute Receipt.chain_valid?([s1, r2, s3], key: @key, require_signature: true)

      # a re-sealed middle receipt keeping the old signature
      forged = %{s2 | row_count: 999}
      forged = %{forged | sha256: Receipt.compute_sha256(forged)}
      forged = %{forged | id: "vkg-receipt-" <> binary_part(forged.sha256, 0, 20)}
      refute Receipt.chain_valid?([s1, forged, s3], key: @key)

      # signatures do not save a broken link
      refute Receipt.chain_valid?([s1, s3], key: @key)
    end

    test "Session.verify and VKG.verify honour key / require_signature; JSON keeps the signature" do
      {_c, plan} = plan(["customer"])
      catalog = catalog(["customer"])
      {:ok, result, obs} = Executor.execute(plan, engine: @fake)
      receipt = Receipt.build(plan, result, obs)
      {:ok, signed} = Receipt.sign(receipt, @key)

      unsigned_session = Session.new(catalog, plan, result, obs, receipt)
      signed_session = Session.new(catalog, plan, result, obs, signed)

      assert :ok = AshR2RML.VKG.verify(unsigned_session)
      assert :ok = AshR2RML.VKG.verify(signed_session)
      assert :ok = AshR2RML.VKG.verify(signed_session, key: @key, require_signature: true)
      assert :ok = Session.verify(signed_session, key: @key)

      assert {:error, %Refusal{code: :REFUSED_VKG_REPLAY, subject: :signature}} =
               AshR2RML.VKG.verify(unsigned_session, key: @key, require_signature: true)

      tampered = %{signed_session | receipt: %{signed | signature: "hmac-sha256:" <> String.duplicate("f", 64)}}

      assert {:error, %Refusal{code: :REFUSED_VKG_REPLAY, subject: :signature}} =
               AshR2RML.VKG.verify(tampered, key: @key)

      assert {:error, %Refusal{code: :REFUSED_VKG_QUERY_PLAN}} = AshR2RML.VKG.verify(signed_session, [:x])

      rjson = Serializer.encode_receipt!(signed)
      resjson = Serializer.encode_result!(result)
      assert {:ok, ^signed} = Serializer.decode_receipt(rjson)
      assert :ok = Serializer.verify_receipt_json(rjson, resjson, plan)
      assert :ok = Serializer.verify_receipt_json(rjson, resjson, plan, key: @key, require_signature: true)

      bad =
        rjson |> Jason.decode!() |> Map.put("signature", "hmac-sha256:" <> String.duplicate("1", 64)) |> Jason.encode!()

      assert {:error, %Refusal{subject: :signature}} =
               Serializer.verify_receipt_json(bad, resjson, plan, key: @key)

      no_sig = rjson |> Jason.decode!() |> Map.put("signature", 5) |> Jason.encode!()
      assert {:error, %Refusal{code: :REFUSED_VKG_REPLAY}} = Serializer.decode_receipt(no_sig)
    end

    defp sign_all(receipts) do
      signed =
        Enum.map(receipts, fn receipt ->
          {:ok, s} = Receipt.sign(receipt, @key)
          s
        end)

      {:ok, signed}
    end
  end

  describe "8. Executor.replay/3 verifies recorded evidence" do
    test "replay is a documented public function" do
      assert function_exported?(Executor, :replay, 3)
      {:docs_v1, _, _, _, _, _, docs} = Code.fetch_docs(Executor)

      assert {{:function, :replay, 3}, _, _, %{"en" => doc}, _} =
               Enum.find(docs, &match?({{:function, :replay, 3}, _, _, _, _}, &1))

      assert doc =~ "not trusted"
    end

    test "honest recordings replay; a live claim needs an :ontop system process" do
      {plan, result, obs, _receipt} = sealed_double()
      assert {:ok, rebuilt, _} = Executor.replay(plan, Replay.RecordedEngine, recorded_observations: obs)
      assert rebuilt.sha256 == result.sha256

      forged =
        Map.new(obs, fn {id, o} ->
          {id, %{o | evidence_kind: :system_process, standing: :obda_query_observed, system: :fake_vkg}}
        end)

      assert {:ok, %{standing: :test_double_only}, _} =
               Executor.replay(plan, Replay.RecordedEngine, recorded_observations: forged)
    end

    test "tampered rows, digests and identity in recordings are refused" do
      {plan, _result, obs, _receipt} = sealed_double()

      rows = put_in(obs, ["customer", Access.key(:rows)], [%{"subject" => "urn:evil"}])

      assert {:error, %Refusal{code: :REFUSED_VKG_REPLAY}} =
               Executor.replay(plan, Replay.RecordedEngine, recorded_observations: rows)

      digest = put_in(obs, ["customer", Access.key(:observation_sha256)], nil)

      assert {:error, %Refusal{code: :REFUSED_VKG_REPLAY}} =
               Executor.replay(plan, Replay.RecordedEngine, recorded_observations: digest)

      drift = put_in(obs, ["customer", Access.key(:mapping_sha256)], String.duplicate("e", 64))

      assert {:error, %Refusal{code: :REFUSED_VKG_SOURCE_DRIFT}} =
               Executor.replay(plan, Replay.RecordedEngine, recorded_observations: drift)

      assert {:error, %Refusal{code: :REFUSED_VKG_REPLAY}} = Replay.reconstruct(plan, rows)

      assert {:error, %Refusal{}} =
               Executor.replay(%{plan | id: "x"}, Replay.RecordedEngine, recorded_observations: obs)

      assert {:error, %Refusal{}} = Executor.replay(plan, Replay.RecordedEngine, :not_keyword)
    end
  end

  describe "9. inspection, batch and engineering hardening" do
    @describetag :tmp_dir

    test "Inspection.snapshot surfaces ontology_sha256 for catalogs and sessions", %{tmp_dir: dir} do
      {:ok, catalog} = Catalog.new([real_contract(dir), real_contract(dir, "order", false)])
      snap = Inspection.snapshot(catalog)
      by_id = Map.new(snap.contracts, &{&1.id, &1})
      assert by_id["customer"].ontology_sha256 == sha("# ontology customer\n")
      assert Map.has_key?(by_id["order"], :ontology_sha256)
      assert by_id["order"].ontology_sha256 == nil

      {:ok, plan} = Planner.plan(catalog, ["customer"])
      {:ok, result, obs} = Executor.execute(plan, engine: @fake)
      session = Session.new(catalog, plan, result, obs, Receipt.build(plan, result, obs))
      [stage] = Inspection.snapshot(session).stages
      assert stage.ontology_sha256 == sha("# ontology customer\n")
    end

    test "batch turns every malformed input into a typed refusal" do
      assert %{admitted: [], refused: [%{reason: %Refusal{code: :REFUSED_VKG_QUERY_SCOPE}}]} = Batch.run(:nope)
      assert %{refused: [%{reason: %Refusal{code: :REFUSED_VKG_QUERY_PLAN}}]} = Batch.run([], [1, 2])
      assert %{refused: [%{reason: %Refusal{code: :REFUSED_VKG_QUERY_PLAN}}]} = Batch.run([], :x)

      for bad <- [0, -1, :many, nil, 1.5] do
        assert %{refused: [%{reason: %Refusal{code: :REFUSED_VKG_QUERY_PLAN, subject: :max_requests}}]} =
                 Batch.run([], max_requests: bad)
      end

      out =
        Batch.run(
          [
            %{contracts: :customer},
            %{contracts: ["customer"], opts: :nope},
            %{contracts: ["customer"], opts: [1, 2]},
            %{contracts: ["customer"], opts: %{engine: @fake}},
            %{"contracts" => nil},
            [:list],
            "str",
            nil,
            %{contracts: ["customer"], opts: [engine: @fake]},
            %{contracts: ["customer"], opts: nil}
          ],
          engine: @fake
        )

      assert length(out.admitted) == 2
      assert Enum.map(out.refused, & &1.index) == [0, 1, 2, 3, 4, 5, 6, 7]
      assert Enum.all?(out.refused, &match?(%Refusal{}, &1.reason))
      assert Enum.map(out.admitted, & &1.index) == [8, 9]
    end

    test "batch turns an engine exception into a refusal, not a raise" do
      defmodule Boom do
        def execute(_stage, _opts), do: raise("kaboom")
      end

      assert %{admitted: [], refused: [%{reason: %Refusal{code: :REFUSED_VKG_EXECUTION}}]} =
               Batch.run([%{contracts: ["customer"], opts: [engine: Boom]}])
    end

    test "Engineering.snapshot and source_trace tolerate non-map rows" do
      catalog = catalog(["customer"])
      {:ok, plan} = Planner.plan(catalog, ["customer"])
      {:ok, result, obs} = Executor.execute(plan, engine: @fake)

      odd = [
        "just a string",
        5,
        nil,
        [1, 2],
        %{"_vkg" => "not a map"},
        %{"_vkg" => %{"subject" => 7}},
        %{"_vkg" => %{"subject" => "urn:ok"}, "x" => 1}
      ]

      session =
        Session.new(catalog, plan, %{result | rows: odd, row_count: length(odd)}, obs, Receipt.build(plan, result, obs))

      snapshot = Engineering.snapshot(session)
      assert snapshot["row_count"] == length(odd)
      assert Map.has_key?(snapshot["entities"], "urn:ok")
      assert snapshot["entity_count"] == 6
      assert Enum.all?(Map.keys(snapshot["entities"]), &is_binary/1)
      assert is_list(Engineering.subjects(session))
      assert [%{"subject" => "urn:ok"}] = Engineering.source_trace(session, "urn:ok")
      assert Engineering.source_trace(session, "urn:none") == []
    end
  end

  describe "10. documentation states the new truth" do
    defp read(rel), do: File.read!(Path.join(@root, rel))

    test "CHANGELOG lists exactly the versions with release commits and records the residual closure" do
      changelog = read("CHANGELOG.md")
      refute changelog =~ "26.9.26 - 26.9.27: no release commits found in git history"
      assert changelog =~ "Residual-risk closure"
      assert changelog =~ "release commits"
      assert changelog =~ "26.9.12"
      assert changelog =~ "26.9.24"
      assert changelog =~ "no git tags"

      for topic <- ["snapshot", "catalog", "canonical", "signature", "Executor.replay", "ontology_sha256", "Batch"] do
        assert changelog =~ topic, "CHANGELOG residual entry must mention #{topic}"
      end
    end

    test "usage rules and PRD/ARD no longer claim the closed residuals" do
      vkg = read("usage-rules/vkg.md")
      refute vkg =~ "Residual: with no signatures"
      assert vkg =~ "shared-key MAC"
      assert vkg =~ "not a public-key signature"
      assert vkg =~ "snapshot"

      for doc <- [
            "docs/jira/v26.9.28/VKG-001-virtual-knowledge-graph-federation-PRD.md",
            "docs/jira/v26.9.28/VKG-001-virtual-knowledge-graph-federation-ARD.md"
          ] do
        text = read(doc)
        assert text =~ "shared-key MAC"
        assert text =~ "TOCTOU"
        refute text =~ "lossy"
      end

      refute read("lib/ash_r2rml/vkg/serializer.ex") =~ "share the encoding of their string form"
    end
  end

  # mix test turns debug_info off; Code.Typespec needs it in the compiled beam.
  defp compile_with_debug_info(source) do
    previous = Code.get_compiler_option(:debug_info)
    Code.put_compiler_option(:debug_info, true)

    try do
      Code.compile_string(source)
    after
      Code.put_compiler_option(:debug_info, previous)
    end
  end

  defp sealed_double do
    {_c, plan} = plan(["customer"])
    {:ok, result, obs} = Executor.execute(plan, engine: @fake)
    {plan, result, obs, Receipt.build(plan, result, obs)}
  end
end
