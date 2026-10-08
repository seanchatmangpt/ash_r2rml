defmodule AshR2RML.AIRoRiskDescriptionTest do
  @moduledoc """
  Court for priv/airo_risk_description.ttl (lane W625d, AIRo wiring wave).

  Chicago-style: asserts on the real on-disk TTL, the real vendored AIRo
  vocabulary snapshot, and the real cited source paths. No mocks.
  """

  use ExUnit.Case, async: true

  @description_path "priv/airo_risk_description.ttl"
  @vocabulary_path "test/fixtures/airo_vocabulary_snapshot.ttl"
  @vocabulary_sha256 "6274d2d8711e046cf38f1b5b2980188094d4aa87b5af79804005a06468fd8469"

  @repo_root File.cwd!()

  describe "AIRo risk description" do
    test "exists and is non-empty" do
      assert File.exists?(path(@description_path))
      content = File.read!(path(@description_path))
      assert byte_size(content) > 1_000
    end

    test "is structurally well-formed Turtle (prefixes declared, delimiters balanced)" do
      content = File.read!(path(@description_path))

      # Every used prefix is declared.
      used_prefixes =
        Regex.scan(~r/^@prefix\s+([a-z0-9_-]+):/m, content)
        |> MapSet.new(fn [_ | [p]] -> p end)

      referenced_prefixes =
        Regex.scan(~r/(?<![\w.\/])([a-z0-9_-]+):[A-Za-z][A-Za-z0-9_-]*/, content)
        |> MapSet.new(fn [_ | [p]] -> p end)

      # rdf:/rdfs:/xsd: etc. appear inside comments too — only require that
      # every referenced prefix has a declaration or is an IRI scheme match.
      iri_schemes = MapSet.new(["http", "https", "urn"])
      undeclared = MapSet.difference(referenced_prefixes, MapSet.union(used_prefixes, iri_schemes))
      assert MapSet.size(undeclared) == 0, "undeclared prefixes: #{inspect(undeclared)}"

      # Delimiters balanced: <> pairs, and statement-terminating periods present.
      assert content |> count("<") == count_content_gt(content)
      assert count(content, " .") > 0
      assert String.contains?(content, "rdf:type airo:AISystem")
    end

    test "types the system as an airo:AISystem with risks and controls" do
      content = File.read!(path(@description_path))

      assert String.contains?(content, "airo:AISystem")
      assert String.contains?(content, "airo:Risk")
      assert String.contains?(content, "airo:RiskSource") or String.contains?(content, "airo:Hazard")
      assert String.contains?(content, "airo:RiskControl")
      assert String.contains?(content, "airo:Consequence")
      assert String.contains?(content, "airo:Likelihood") and String.contains?(content, "airo:Severity")
      assert String.contains?(content, "airo:hasRiskControl")
    end

    test "every cited repo path exists on disk" do
      content = File.read!(path(@description_path))

      cited =
        Regex.scan(~r{(lib|test)/[\w./-]+}, content)
        |> Enum.map(fn p -> String.trim_trailing(List.first(p), ".") end)
        |> Enum.uniq()
        |> Enum.reject(&(&1 == ""))

      assert cited != [], "no repo paths cited in the description"

      missing =
        cited
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&File.exists?(path(&1)))

      assert missing == [], "cited paths missing on disk: #{inspect(missing)}"
    end

    test "every airo: term used is in the fetched AIRo vocabulary" do
      description = File.read!(path(@description_path))
      vocabulary = File.read!(path(@vocabulary_path))

      vocabulary_terms = airo_terms(vocabulary)
      assert MapSet.size(vocabulary_terms) > 50

      used_terms = airo_terms(description)
      unknown = MapSet.difference(used_terms, vocabulary_terms)
      assert MapSet.size(unknown) == 0,
             "terms not in AIRo vocabulary: #{inspect(MapSet.to_list(unknown))}"
    end

    test "vocabulary snapshot matches the fetched airo.ttl sha256" do
      assert :crypto.hash(:sha256, File.read!(path(@vocabulary_path)))
             |> Base.encode16(case: :lower) == @vocabulary_sha256
    end
  end

  defp airo_terms(ttl) do
    ttl
    # strip comments so commented examples don't count as vocabulary
    |> String.split("\n")
    |> Enum.reject(&String.starts_with?(String.trim_leading(&1), "#"))
    |> Enum.join("\n")
    |> then(&Regex.scan(~r/airo:([A-Za-z][A-Za-z0-9_]*)/, &1))
    |> MapSet.new(fn [_ | [term]] -> term end)
  end

  defp count(string, sub), do: length(:binary.matches(string, sub))

  defp count_content_gt(content) do
    # strip comment lines first so '>' inside comments is not counted
    content
    |> String.split("\n")
    |> Enum.reject(&String.starts_with?(String.trim_leading(&1), "#"))
    |> Enum.join("\n")
    |> count(">")
  end

  defp path(relative), do: Path.join(@repo_root, relative)
end
