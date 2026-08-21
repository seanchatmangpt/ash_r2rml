# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenProductionTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Ggen.Production

  defmodule Account do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :account_number, :string, allow_nil?: false, public?: true
    end

    r2rml do
      table_name("accounts")
      class("https://example.test/ontology/Account")

      subject do
        template("https://example.test/account/{id}")
      end

      property(:account_number, "https://example.test/ontology/accountNumber")
    end
  end

  test "production compiler constructs dynamic inputs for the repo-level ggen workspace" do
    assert {:ok, result} = Production.compile(Account)

    assert result.status == :PARTIAL_ALIVE
    assert result.standing == :construct_only
    assert result.workspace == "production/ggen/ggen.toml"
    assert result.receipt.standing == :construct_only_ggen_input
    assert result.files["production/ggen/input.ttl"] =~ "AdmittedSemanticSubject"
    assert result.files["production/ggen/input.ttl"] =~ "DesignCandidate"
    assert result.files["production/ggen/input.ttl"] =~ "AuthorityBoundary"
  end

  test "dynamic production RDF is standards-parseable" do
    assert {:ok, result} = Production.compile(Account)
    ttl = result.files["production/ggen/input.ttl"]

    assert {:ok, _graph} = RDF.Turtle.read_string(ttl)
  end

  test "same admitted subject produces byte-identical dynamic inputs" do
    assert {:ok, first} = Production.compile(Account)
    assert {:ok, second} = Production.compile(Account)

    assert first.files == second.files
    assert first.sha256 == second.sha256
    assert first.receipt.receipt_sha256 == second.receipt.receipt_sha256
  end

  test "all generated JSON inputs are valid JSON" do
    assert {:ok, result} = Production.compile(Account)

    result.files
    |> Enum.filter(fn {path, _content} -> String.ends_with?(path, ".json") end)
    |> Enum.each(fn {_path, content} -> assert {:ok, _decoded} = Jason.decode(content) end)
  end

  test "staged hash verifier refuses missing, extra and changed inputs" do
    assert {:ok, result} = Production.compile(Account)
    assert {:ok, %{status: :ALIVE}} = Production.verify_staged(result, result.sha256)

    [{path, _hash} | _] = Enum.to_list(result.sha256)
    changed = Map.put(result.sha256, path, String.duplicate("0", 64))

    assert {:error, %{code: :REFUSED_GGEN_STAGED_HASH_MISMATCH}} =
             Production.verify_staged(result, changed)
  end

  test "workspace contract names are stable and contain no company-size quality namespace" do
    files = Production.workspace_files()

    assert "production/ggen/ggen.toml" in files
    refute Enum.any?(files, &String.contains?(String.downcase(&1), "fortune"))
  end
end
