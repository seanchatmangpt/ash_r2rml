# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.VKG.V26928AdmissionTest do
  use ExUnit.Case, async: true

  import AshR2RML.VKGCase

  alias AshR2RML.Refusal
  alias AshR2RML.VKG.{Catalog, Compatibility, Contract, Manifest, Planner, QueryPlan, Registry}
  alias AshR2RML.VKG.SourceIdentity

  @moduletag :tmp_dir

  defp write_root(dir, overrides \\ %{}, files \\ %{}) do
    File.mkdir_p!(Path.join(dir, "sources"))
    File.mkdir_p!(Path.join(dir, "mappings"))
    File.mkdir_p!(Path.join(dir, "queries"))
    File.mkdir_p!(Path.join(dir, "ontology"))
    File.write!(Path.join(dir, "mappings/a.ttl"), "@prefix ex: <urn:ex:> .\n")
    File.write!(Path.join(dir, "queries/a.rq"), "CONSTRUCT { ?s ?p ?o } WHERE { ?s ?p ?o }\n")
    File.write!(Path.join(dir, "ontology/o.ttl"), "# ontology v1\n")
    for {path, bytes} <- files, do: File.write!(Path.join(dir, path), bytes)

    manifest =
      Map.merge(
        %{
          "id" => "a",
          "source" => "urn:source:a",
          "graph" => "urn:graph:a",
          "subject_template" => "https://example.org/a/{id}",
          "mapping" => "mappings/a.ttl",
          "query" => "queries/a.rq",
          "ontology" => "ontology/o.ttl",
          "capabilities" => ["select", "filter"]
        },
        overrides
      )

    manifest = Map.reject(manifest, fn {_k, v} -> v == :drop end)
    File.write!(Path.join(dir, "sources/a.json"), Jason.encode!(manifest))
    dir
  end

  defp load(dir), do: Manifest.load(Path.join(dir, "sources/a.json"), dir)

  defp code({:error, %Refusal{code: code}}), do: code
  defp code({:error, %Refusal{code: code, subject: subject}}, :subject), do: {code, subject}

  describe "manifest refusals" do
    test "happy path binds ontology bytes", %{tmp_dir: dir} do
      assert {:ok, c} = dir |> write_root() |> load()
      assert c.ontology_sha256 == :crypto.hash(:sha256, "# ontology v1\n") |> Base.encode16(case: :lower)
      assert c.capabilities == [:filter, :select]
    end

    test "path traversal refused", %{tmp_dir: dir} do
      write_root(dir, %{"mapping" => "../x"})
      assert {:REFUSED_VKG_MANIFEST, :mapping} = code(load(dir), :subject)
    end

    test "missing mapping file refused", %{tmp_dir: dir} do
      write_root(dir, %{"mapping" => "mappings/none.ttl"})
      assert {:REFUSED_VKG_MANIFEST, :mapping} = code(load(dir), :subject)
    end

    test "non-string mapping refused", %{tmp_dir: dir} do
      write_root(dir, %{"mapping" => 5})
      assert {:REFUSED_VKG_MANIFEST, :mapping} = code(load(dir), :subject)
    end

    test "invalid JSON and non-object JSON refused", %{tmp_dir: dir} do
      write_root(dir)
      File.write!(Path.join(dir, "sources/a.json"), "{nope")
      assert {:REFUSED_VKG_MANIFEST, :source_manifest} = code(load(dir), :subject)
      File.write!(Path.join(dir, "sources/a.json"), "[1]")
      assert {:REFUSED_VKG_MANIFEST, :source_manifest} = code(load(dir), :subject)
    end

    test "empty root refused with subject :sources", %{tmp_dir: dir} do
      assert {:REFUSED_VKG_MANIFEST, :sources} = code(Manifest.load_all(dir), :subject)
      assert :REFUSED_VKG_MANIFEST = code(Manifest.load_all(:nope))
      assert :REFUSED_VKG_MANIFEST = code(Manifest.load(nil, dir))
    end

    test "symlink inside root pointing outside is refused", %{tmp_dir: dir} do
      outside = Path.join(dir, "outside.ttl")
      File.write!(outside, "x")
      root = Path.join(dir, "root")
      write_root(root)
      File.rm!(Path.join(root, "mappings/a.ttl"))
      File.ln_s!(outside, Path.join(root, "mappings/a.ttl"))
      assert {:REFUSED_VKG_MANIFEST, :mapping} = code(load(root), :subject)
    end

    test "sibling-prefix root and manifest outside sources refused", %{tmp_dir: dir} do
      root = Path.join(dir, "vkg")
      evil = Path.join(dir, "vkg-evil")
      write_root(root)
      write_root(evil)
      File.write!(Path.join(evil, "x.ttl"), "x")
      write_root(root, %{"mapping" => "../vkg-evil/x.ttl"})
      assert :REFUSED_VKG_MANIFEST = code(load(root))
      assert :REFUSED_VKG_MANIFEST = code(Manifest.load(Path.join(evil, "sources/a.json"), root))
    end

    test "non-string version refused", %{tmp_dir: dir} do
      write_root(dir, %{"version" => 1})
      assert {:REFUSED_VKG_MANIFEST, :version} = code(load(dir), :subject)
    end

    test "authority key is ignored: contract stays :NONE", %{tmp_dir: dir} do
      write_root(dir, %{"authority" => "write"})
      assert {:ok, %Contract{authority: :NONE}} = load(dir)
    end
  end

  describe "capabilities (closed allowlist)" do
    test "unknown, invalid and non-list capabilities refused at manifest", %{tmp_dir: dir} do
      for bad <- [["write"], [1], "select", [], ["select", nil]] do
        write_root(dir, %{"capabilities" => bad})
        assert :REFUSED_VKG_CAPABILITY = code(load(dir))
      end
    end

    test "contract admission refuses extension and invalid capabilities" do
      for bad <- [[{:extension, "write"}], [{:invalid, 1}], [:write], [], :select, [:select, :select]] do
        assert {:error, %Refusal{code: :REFUSED_VKG_CAPABILITY}} =
                 Contract.admit(contract("x", capabilities: bad))
      end
    end

    test "planner refuses unknown and non-atom requested capability" do
      catalog = catalog(["customer"])

      for cap <- [:write, "select", 1, nil] do
        assert {:error, %Refusal{code: :REFUSED_VKG_CAPABILITY}} =
                 Planner.plan(catalog, ["customer"], capability: cap)
      end
    end

    test "requested capability and capability set change the plan hash" do
      {:ok, cat} = Catalog.new([contract("a", capabilities: [:select, :join])])
      {:ok, p1} = Planner.plan(cat, ["a"], capability: :select)
      {:ok, p2} = Planner.plan(cat, ["a"], capability: :join)
      assert p1.sha256 != p2.sha256
      assert p2.capability == :join
      assert p2.capabilities == [:join, :select]
      assert :ok = QueryPlan.verify(p2)
      assert {:error, %Refusal{}} = QueryPlan.verify(%{p2 | capability: :filter})
    end

    test "widening capabilities changes contract digest and catalog identity" do
      {:ok, c1} = Catalog.new([contract("a", capabilities: [:select])])
      {:ok, c2} = Catalog.new([contract("a", capabilities: [:select, :join])])
      assert c1.sha256 != c2.sha256
    end
  end

  describe "ontology identity" do
    test "ontology digest feeds contract digest, catalog sha and plan", %{tmp_dir: dir} do
      {:ok, c1} = dir |> write_root() |> load()
      File.write!(Path.join(dir, "ontology/o.ttl"), "# ontology v2\n")
      {:ok, c2} = load(dir)
      assert c1.ontology_sha256 != c2.ontology_sha256
      assert Contract.digest(c1) != Contract.digest(c2)
      {:ok, k1} = Catalog.new([c1])
      {:ok, k2} = Catalog.new([c2])
      assert k1.sha256 != k2.sha256
      {:ok, p} = Planner.plan(k2, ["a"])
      assert p.ontology_sha256 == hash_of([c2.ontology_sha256])
      assert Contract.identity(c2).ontology_sha256 == c2.ontology_sha256
      assert Manifest.snapshot(c2).ontology_sha256 == c2.ontology_sha256
    end

    test "ontology path without digest is refused" do
      c = %{contract("x") | ontology_path: "/tmp/o.ttl"}
      assert {:error, %Refusal{code: :REFUSED_VKG_CONTRACT_IDENTITY}} = Contract.admit(c)
    end

    test "missing ontology file refused", %{tmp_dir: dir} do
      write_root(dir, %{"ontology" => "ontology/none.ttl"})
      assert {:REFUSED_VKG_MANIFEST, :ontology} = code(load(dir), :subject)
    end
  end

  defp hash_of(term),
    do: :crypto.hash(:sha256, :erlang.term_to_binary(term, [:deterministic])) |> Base.encode16(case: :lower)

  describe "plan digest is host independent and bound to contracts" do
    test "differing absolute paths give identical plan digest and id" do
      base = contract("a")
      moved = %{base | mapping_path: "/elsewhere/a.ttl", query_path: "/elsewhere/a.rq"}
      {:ok, c1} = Catalog.new([base])
      {:ok, c2} = Catalog.new([moved])
      {:ok, p1} = Planner.plan(c1, ["a"])
      {:ok, p2} = Planner.plan(c2, ["a"])
      assert p1.sha256 == p2.sha256
      assert p1.id == p2.id
    end

    test "stages carry the catalog contract digest; tampering is detected" do
      {cat, plan} = plan(["customer"])
      [stage] = plan.stages
      {:ok, c} = Catalog.fetch(cat, "customer")
      assert stage.contract_digest == Contract.digest(c)
      forged = %{plan | stages: [%{stage | contract_digest: String.duplicate("0", 64)}]}
      assert {:error, %Refusal{code: :REFUSED_VKG_QUERY_PLAN}} = QueryPlan.verify(forged)
    end

    test "verify checks id, bounds, merge and shape" do
      {_cat, plan} = plan(["customer"])
      assert {:error, %Refusal{subject: :id}} = QueryPlan.verify(%{plan | id: "vkg-plan-x"})
      assert {:error, %Refusal{}} = QueryPlan.verify(%{plan | max_rows: 0})
      assert {:error, %Refusal{}} = QueryPlan.verify(%{plan | merge: :zip})
      assert {:error, %Refusal{}} = QueryPlan.verify(%{plan | stages: [:junk]})
      assert {:error, %Refusal{}} = QueryPlan.verify(:not_a_plan)
    end
  end

  describe "compatibility enforced in planner" do
    test "mixed versions refused by planner" do
      {:ok, cat} = Catalog.new([contract("a"), %{contract("b") | version: "2"}] |> reidentify())

      assert {:error, %Refusal{code: :REFUSED_VKG_COMPATIBILITY}} =
               Planner.plan(cat, ["a", "b"])
    end

    test "matrix has no self pairs and reports source collision" do
      a = contract("a")
      b = %{contract("b") | source: a.source, source_sha256: String.duplicate("c", 64)}
      assert [pair] = Compatibility.matrix([a, b])
      assert pair.source_collision?
      refute pair.compatible?
      assert {:error, %Refusal{code: :REFUSED_VKG_COMPATIBILITY}} = Compatibility.check([a, b])
    end

    test "compatibility refuses non-contract members" do
      assert {:error, %Refusal{code: :REFUSED_VKG_COMPATIBILITY}} = Compatibility.check([:x])
    end
  end

  defp reidentify(contracts) do
    Enum.map(contracts, fn c ->
      {:ok, i} =
        SourceIdentity.new(%{
          id: c.id,
          uri: c.source,
          graph: c.graph,
          subject_template: c.subject_template,
          version: c.version
        })

      %{c | source_sha256: i.sha256}
    end)
  end

  describe "typed refusals at entry points" do
    test "query scope: empty, duplicate, unknown, non-list, non-binary ids" do
      cat = catalog(["customer"])

      for ids <- [[], ["customer", "customer"], [:customer], "customer", nil, [""]] do
        assert {:error, %Refusal{code: :REFUSED_VKG_QUERY_SCOPE}} = Catalog.select(cat, ids)
        assert {:error, %Refusal{code: :REFUSED_VKG_QUERY_SCOPE}} = Planner.plan(cat, ids)
      end

      assert {:error, %Refusal{code: :REFUSED_VKG_REGISTRY_AMBIGUOUS}} =
               Catalog.select(cat, ["ghost"])

      assert {:error, %Refusal{code: :REFUSED_VKG_QUERY_SCOPE}} = Planner.plan(:nope, ["x"])
      assert {:error, %Refusal{}} = Planner.plan(cat, ["customer"], :bad)
    end

    test "registry fetch with non-binary id is typed" do
      {:ok, reg} = Registry.admit([contract("a")])
      assert {:error, %Refusal{code: :REFUSED_VKG_QUERY_SCOPE}} = Registry.fetch(reg, 123)
      assert {:error, %Refusal{code: :REFUSED_VKG_QUERY_SCOPE}} = Registry.fetch(:x, "a")
    end
  end

  describe "contract shape and identity" do
    test "non-struct and bad standing refused with shape code" do
      assert {:error, %Refusal{code: :REFUSED_VKG_CONTRACT_SHAPE}} = Contract.admit(%{})
      c = %{contract("x") | standing: :actuated}
      assert {:error, %Refusal{code: :REFUSED_VKG_CONTRACT_SHAPE, subject: :standing}} = Contract.admit(c)
      c = %{contract("x") | version: 1}
      assert {:error, %Refusal{code: :REFUSED_VKG_CONTRACT_SHAPE}} = Contract.admit(c)
    end

    test "identity refusals: blank id, bad digest, blank path" do
      for c <- [
            %{contract("x") | id: "  "},
            %{contract("x") | mapping_sha256: "ZZ"},
            %{contract("x") | query_sha256: String.upcase(String.duplicate("a", 64))},
            %{contract("x") | mapping_path: ""}
          ] do
        assert {:error, %Refusal{code: :REFUSED_VKG_CONTRACT_IDENTITY}} = Contract.admit(c)
      end
    end

    test "source identity drift against a tampered descriptor" do
      c = %{contract("x") | graph: "urn:graph:other"}

      assert {:error, %Refusal{code: :REFUSED_VKG_SOURCE_DRIFT}} = Contract.admit(c)
    end

    test "source identity tightening" do
      base = %{id: "a", uri: "urn:x:a", graph: "urn:g:a", subject_template: "t"}
      assert {:ok, _} = SourceIdentity.new(base)

      for bad <- ["urn:", "http://", "https:// x", "urn:x", "http://\n"] do
        assert {:error, %Refusal{code: :REFUSED_VKG_SOURCE_IDENTITY}} =
                 SourceIdentity.new(%{base | uri: bad})
      end

      assert {:error, %Refusal{subject: :version}} = SourceIdentity.new(Map.put(base, :version, 1))
      assert {:error, %Refusal{subject: :version}} = SourceIdentity.new(Map.put(base, :version, ""))
    end
  end

  describe "registry ambiguity" do
    test "same source URI with different graph refused" do
      a = contract("a", source: "urn:source:shared")
      b = contract("b", source: "urn:source:shared")
      assert {:error, %Refusal{code: :REFUSED_VKG_REGISTRY_AMBIGUOUS, subject: :sources}} = Registry.admit([a, b])
    end

    test "same graph with different ids refused; empty and non-list refused" do
      a = contract("a", graph: "urn:graph:shared")
      b = contract("b", graph: "urn:graph:shared")
      assert {:error, %Refusal{code: :REFUSED_VKG_REGISTRY_AMBIGUOUS, subject: :graphs}} = Registry.admit([a, b])
      assert {:error, %Refusal{code: :REFUSED_VKG_REGISTRY_AMBIGUOUS}} = Registry.admit([])
      assert {:error, %Refusal{code: :REFUSED_VKG_REGISTRY_AMBIGUOUS}} = Registry.admit(:x)
    end

    test "duplicate ids refused and invalid member propagates" do
      assert {:error, %Refusal{code: :REFUSED_VKG_REGISTRY_AMBIGUOUS, subject: :ids}} =
               Registry.admit([contract("a"), contract("a")])

      assert {:error, %Refusal{code: :REFUSED_VKG_CONTRACT_SHAPE}} = Registry.admit([contract("a"), :bogus])
    end
  end

  describe "source drift against artifact bytes" do
    test "changed mapping bytes change contract identity and catalog sha", %{tmp_dir: dir} do
      {:ok, c1} = dir |> write_root() |> load()
      File.write!(Path.join(dir, "mappings/a.ttl"), "# drifted\n")
      {:ok, c2} = load(dir)
      assert c1.mapping_sha256 != c2.mapping_sha256
      {:ok, k1} = Catalog.new([c1])
      {:ok, k2} = Catalog.new([c2])
      assert k1.sha256 != k2.sha256
    end

    test "descriptor digest mismatch is REFUSED_VKG_SOURCE_DRIFT", %{tmp_dir: dir} do
      {:ok, c} = dir |> write_root() |> load()
      forged = %{c | source_sha256: String.duplicate("f", 64)}
      assert {:error, %Refusal{code: :REFUSED_VKG_SOURCE_DRIFT}} = Contract.admit(forged)
    end

    test "catalog loaded from a copied root has the same sha as the default root", %{tmp_dir: dir} do
      File.cp_r!(Manifest.default_root(), dir)
      assert {:ok, a} = Catalog.load(Manifest.default_root())
      assert {:ok, b} = Catalog.load(dir)
      assert a.sha256 == b.sha256
      assert {:ok, %{contracts: [_ | _]}} = {:ok, Catalog.snapshot(b)}
    end
  end
end
