defmodule AshR2RML.AIRoWiringLedgerPinW685Test do
  @moduledoc """
  Lane W685 pin court for the AIRo wiring ledger row (w625d) of ash_r2rml.

  Asserts the ledger's CONSISTENT claim against the real on-disk surface:
  the fixture copy of the vendored airo.ttl is byte-identical to the
  cross-repo pin (6274d2d8…), parses as Turtle, and every repository path
  the risk description cites exists on disk. Real file reads only, no mocks.
  """

  use ExUnit.Case, async: true

  @repo_root File.cwd!()

  @fixture_path "test/fixtures/airo_vocabulary_snapshot.ttl"
  @description_path "priv/airo_risk_description.ttl"

  # AIRo wiring ledger, cross-repo sha consistency table (w600/w621b pin).
  @ledger_pin_sha256 "6274d2d8711e046cf38f1b5b2980188094d4aa87b5af79804005a06468fd8469"

  # Sibling xaas checkout's vendored canonical copy (cross-repo drift check).
  @vendored_xaas_path "/Users/sac/xaas/priv/semantic/airo/airo.ttl"

  describe "AIRo wiring ledger pin (W685)" do
    test "fixture snapshot is byte-identical to the ledger pin sha256" do
      content = File.read!(path(@fixture_path))

      assert byte_size(content) > 0
      assert :crypto.hash(:sha256, content) |> Base.encode16(case: :lower) ==
               @ledger_pin_sha256
    end

    test "fixture snapshot parses as the real AIRo vocabulary (classes + object properties)" do
      content = File.read!(path(@fixture_path))

      # Real parse of the TTL structure, not a byte-count proxy.
      assert String.contains?(content, "@prefix airo:")

      classes =
        Regex.scan(~r/^airo:([A-Za-z][A-Za-z0-9_]*)\s+rdf:type\s+owl:Class/m, content)
        |> MapSet.new(fn [_ | [term]] -> term end)

      object_properties =
        Regex.scan(~r/^airo:([A-Za-z][A-Za-z0-9_]*)\s+rdf:type\s+owl:ObjectProperty/m, content)
        |> MapSet.new(fn [_ | [term]] -> term end)

      assert MapSet.size(classes) >= 20,
             "expected >=20 owl:Class declarations, got #{MapSet.size(classes)}"

      assert MapSet.size(object_properties) >= 10,
             "expected >=10 owl:ObjectProperty declarations, got #{MapSet.size(object_properties)}"

      # Anchor terms the ledger's AISystem risk model depends on.
      for anchor <- ~w(AISystem Risk RiskControl Consequence) do
        assert MapSet.member?(classes, anchor), "missing owl:Class airo:#{anchor}"
      end

      for anchor <- ~w(hasRiskControl hasConsequence) do
        assert MapSet.member?(object_properties, anchor),
               "missing owl:ObjectProperty airo:#{anchor}"
      end
    end

    test "fixture is byte-identical to the vendored canonical airo.ttl in the xaas checkout" do
      assert File.exists?(@vendored_xaas_path),
             "vendored canonical copy missing at #{@vendored_xaas_path}"

      assert File.read!(@vendored_xaas_path) == File.read!(path(@fixture_path)),
             "fixture drifted from the vendored canonical airo.ttl"
    end

    test "risk description parses and grounds its citations in real repo paths" do
      content = File.read!(path(@description_path))

      assert String.contains?(content, "rdf:type airo:AISystem")

      cited =
        Regex.scan(~r{(lib|test)/[\w./-]+}, content)
        |> Enum.map(&List.first/1)
        |> Enum.map(&String.trim_trailing(&1, "."))
        |> Enum.uniq()
        |> Enum.reject(&(&1 == ""))

      assert cited != [], "risk description cites no repo paths"

      missing = Enum.reject(cited, &File.exists?(path(&1)))
      assert missing == [], "cited paths missing on disk: #{inspect(missing)}"
    end
  end

  defp path(relative), do: Path.join(@repo_root, relative)
end
