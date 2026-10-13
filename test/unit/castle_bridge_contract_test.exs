# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.CastleBridgeContractTest do
  # Not async: spawns real git over the shared checkout.
  use ExUnit.Case, async: false

  @moduledoc """
  Reverse-trust court for `ontology/castle_bridge_contract.ttl` (audit
  finding #3: the consumer packs pin ash_r2rml's sha but ash_r2rml recorded
  nothing back). Every mirrored observation must:

  1. record a 40-hex sha, an owning repo, and an as-of date;
  2. when the sha resolves to a commit in THIS repository, match the live
     HEAD — unless allowlisted as known-stale with an as-of date;
  3. when the sha is external, still be structurally well-formed and
     as-of dated (resolution happens in the owning repo's own court).

  Follows the ggen_runtime ancestry court pattern
  (`test/unit/ggen_runtime_ancestry_test.exs`): stale-but-documented emits a
  warning, undocumented staleness fails closed.
  """

  @contract Path.join(["ontology", "castle_bridge_contract.ttl"])
  @today "2026-10-13"

  # Known-stale allowlist: {sha => %{as_of: date, reason}}. Refreshing the
  # mirror (or adding a NEW stale sha) requires a fresh entry with a fresh
  # as-of date.
  @staleness_allowlist %{
    # xcb:ashR2rmlSha pinned by packs/xaas-castle-bridge-pack; consumer-side
    # regen of the pack pin pending.
    "067954ad406fd637fd47646bdb10c4580809c79d" => %{
      as_of: "2026-10-13",
      reason: "consumer pack pin predates dev HEAD; pack-side regen pending"
    }
  }

  defp read_contract, do: File.read!(Path.expand(@contract, File.cwd!()))

  defp observations do
    read_contract()
    |> then(fn text ->
      Regex.scan(
        ~r/ar:(?<name>observed-[a-z0-9-]+)\s+a\s+skos:Concept\s*;(?<body>.*?)\.\s*\n/s,
        text
      )
      |> Enum.map(fn [_all, name, body] ->
        sha = regex_one(body, ~r/ar:sha\s+"([0-9a-f]{40})"/)
        repo = regex_one(body, ~r/ar:repo\s+"([^"]+)"/)
        as_of = regex_one(body, ~r/ar:observedAsOf\s+"(\d{4}-\d{2}-\d{2})"/)
        external = regex_one(body, ~r/ar:external\s+(true|false)/) == "true"
        %{name: name, sha: sha, repo: repo, as_of: as_of, external: external}
      end)
    end)
  end

  defp regex_one(text, regex) do
    case Regex.run(regex, text) do
      [_, captured] -> captured
      _ -> nil
    end
  end

  defp git(args) do
    {out, 0} = System.cmd("git", args, cd: File.cwd!(), stderr_to_stdout: true)
    String.trim(out)
  end

  defp resolve_full(sha) do
    case System.cmd("git", ["rev-parse", "--verify", sha], cd: File.cwd!(), stderr_to_stdout: true) do
      {full, 0} -> {:ok, String.trim(full)}
      {_err, _} -> :error
    end
  end

  test "contract file exists and is non-empty" do
    assert read_contract() != ""
  end

  test "every observation records sha, repo, and as-of date" do
    obs = observations()

    assert length(obs) >= 4,
           "expected at least the four xcb:bridge mirror observations, found #{length(obs)}"

    for o <- obs do
      assert o.sha =~ ~r/^[0-9a-f]{40}$/, "#{o.name}: sha not a 40-hex commit id"
      assert is_binary(o.repo) and o.repo != "", "#{o.name}: missing owning repo"
      assert o.as_of =~ ~r/^\d{4}-\d{2}-\d{2}$/, "#{o.name}: missing as-of date"
      assert o.as_of <= @today, "#{o.name}: as-of #{o.as_of} is in the future"
      assert is_boolean(o.external), "#{o.name}: missing ar:external flag"
    end
  end

  test "mirror matches the consumer pack's recorded shas" do
    pack =
      Path.expand(
        Path.join([File.cwd!(), "..", "ggen-marketplace", "packs", "xaas-castle-bridge-pack", "ontology.ttl"])
      )

    # The pack lives in a sibling checkout; if it is absent, the mirror's
    # prov:wasDerivedFrom URIs are the durable provenance and this check
    # degrades to structural (already covered above).
    if File.exists?(pack) do
      pack_text = File.read!(pack)

      for {prop, obs_name} <- [
            {"xcb:sourceSha", "observed-castle-source-sha"},
            {"xcb:packSha", "observed-pack-sha"},
            {"xcb:ashR2rmlSha", "observed-ash-r2rml-sha"},
            {"xcb:consumerBaseSha", "observed-consumer-base-sha"}
          ] do
        pinned = regex_one(pack_text, ~r/#{prop}\s+"([0-9a-f]{40})"/)

        assert pinned,
               "consumer pack has no #{prop} to mirror"

        mirrored =
          Enum.find(observations(), &(&1.name == obs_name))
          |> Map.fetch!(:sha)

        assert mirrored == pinned,
               "mirror drift: #{obs_name} records #{mirrored} but the consumer pack " <>
                 "records #{pinned} for #{prop}. Apply the manual-sync law."
      end
    else
      IO.puts(:stderr, "CASTLE_BRIDGE_SKIP: consumer pack not found at #{pack}")
    end
  end

  test "repo-local shas match live HEAD unless allowlisted stale" do
    head = git(["rev-parse", "HEAD"])

    for o <- observations(),
        not o.external do
      assert {:ok, full} = resolve_full(o.sha),
             "MIRROR_PIN[#{o.name}]: sha #{o.sha} is marked non-external but does not " <>
               "resolve in this repository (live HEAD #{head})"

      assert byte_size(full) == 40 and full =~ ~r/^[0-9a-f]{40}$/,
             "MIRROR_PIN[#{o.name}]: #{o.sha} does not resolve to a full 40-hex commit"

      is_head = full == head

      if not is_head do
        entry = Map.get(@staleness_allowlist, full)

        assert match?(%{as_of: _}, entry),
               "MIRROR_PIN[#{o.name}]: recorded sha #{full} is stale (live HEAD " <>
                 "#{head}) and not allowlisted. Refresh the mirror to current HEAD, " <>
                 "or add a @staleness_allowlist entry with an as-of date."

        assert entry.as_of <= @today and entry.as_of != "",
               "MIRROR_PIN[#{o.name}]: allowlist entry for #{full} has invalid as-of " <>
                 "date #{inspect(entry.as_of)}"

        IO.puts(
          :stderr,
          "MIRROR_PIN_WARNING[#{o.name}]: sha #{full} allowlisted as of " <>
            "#{entry.as_of} (#{entry.reason}); live HEAD #{head}"
        )
      end
    end
  end
end