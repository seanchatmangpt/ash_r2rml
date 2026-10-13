# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntimeAncestryTest do
  # Not async: spawns real git over the shared checkout.
  use ExUnit.Case, async: false

  @moduledoc """
  Ancestry court for the exact-subject pins in the ggen runtime integration
  surface. Every pin must (a) be a hex sha that resolves to a full 40-hex
  commit, (b) exist in this repository, (c) be an ancestor of the current
  HEAD. A pin that is no longer HEAD (documented drift) fails unless it is
  present in @staleness_allowlist with an as-of date; an allowlisted stale
  pin emits a warning, an un-allowlisted stale pin fails.
  """

  @repo_root File.cwd!()

  # Pin sites: {file, line-anchor regex context}. Pins are extracted from
  # `head: "<hex>"` occurrences in each file.
  @pin_sites [
    "documentation/how_to/ggen_runtime_integration.md",
    "test/unit/ggen_runtime_test.exs"
  ]

  # Documented staleness: {site => %{sha: full-40-hex, as_of: date, reason}}.
  # An entry here means "this pin is known stale as of this date; warn, do
  # not fail". Refreshing the pin (or adding a NEW stale pin) requires a
  # fresh allowlist entry with a fresh as-of date.
  @staleness_allowlist %{
    # Example shape (kept empty while pins are fresh):
    # "documentation/how_to/ggen_runtime_integration.md" => %{
    #   sha: "067954ad406fd637fd47646bdb10c4580809c79d",
    #   as_of: "2026-10-13",
    #   reason: "26.9.28-era pin documented as drifted; pack-side regen pending"
    # }
  }

  @today "2026-10-13"

  defp extract_pins(path) do
    full = Path.join(@repo_root, path)
    assert File.exists?(full), "pin site missing: #{path}"

    full
    |> File.read!()
    |> then(fn text ->
      Regex.scan(~r/head:\s*"([0-9a-fA-F]{8,40})"/, text)
      |> Enum.map(&Enum.at(&1, 1))
      |> Enum.uniq()
    end)
  end

  defp git(args) do
    {out, 0} = System.cmd("git", args, cd: @repo_root, stderr_to_stdout: true)
    String.trim(out)
  end

  defp resolve_full(sha) do
    case System.cmd("git", ["rev-parse", "--verify", sha], cd: @repo_root, stderr_to_stdout: true) do
      {full, 0} -> {:ok, String.trim(full)}
      {_err, _} -> :error
    end
  end

  test "every runtime pin is a full 40-hex commit that exists and is an ancestor of HEAD" do
    head = git(["rev-parse", "HEAD"])

    for site <- @pin_sites do
      for pin <- extract_pins(site) do
        assert pin =~ ~r/^[0-9a-f]{8,40}$/,
               "STALE_PIN[#{site}]: pin #{pin} is not a hex sha"

        assert String.length(pin) >= 8, "STALE_PIN[#{site}]: pin #{pin} too short to be exact"

        assert {:ok, full} = resolve_full(pin),
               "STALE_PIN[#{site}]: pinned sha #{pin} does not exist in this repository " <>
                 "(live HEAD #{head})"

        assert byte_size(full) == 40 and full =~ ~r/^[0-9a-f]{40}$/,
               "STALE_PIN[#{site}]: pin #{pin} does not resolve to a full 40-hex commit " <>
                 "(resolved #{full}, live HEAD #{head})"

        git(["merge-base", "--is-ancestor", full, head])

        is_head = full == head

        if not is_head do
          entry = Map.get(@staleness_allowlist, site)

          assert match?(%{sha: ^full}, entry),
                 "STALE_PIN[#{site}]: pinned sha #{full} is stale (no longer HEAD, live " <>
                   "HEAD #{head}) and is not allowlisted. Refresh the pin to the current " <>
                   "HEAD, or add an @staleness_allowlist entry with an as-of date."

          assert entry.as_of <= @today and entry.as_of != "",
                 "STALE_PIN[#{site}]: allowlist entry for #{full} has invalid as-of " <>
                   "date #{inspect(entry.as_of)}"

          IO.puts(:stderr, "STALE_PIN_WARNING[#{site}]: pin #{full} allowlisted as of " <>
                   "#{entry.as_of} (#{entry.reason}); live HEAD #{head}")
        end
      end
    end
  end

  test "pin sites are non-empty" do
    for site <- @pin_sites do
      assert extract_pins(site) != [], "no pins found in #{site}"
    end
  end

  test "the refreshed integration pin equals live HEAD" do
    head = git(["rev-parse", "HEAD"])

    for site <- @pin_sites do
      pins = extract_pins(site)
      assert head in Enum.map(pins, fn p -> elem(resolve_full(p), 1) end),
             "STALE_PIN[#{site}]: none of #{inspect(pins)} equals live HEAD #{head}"
    end
  end
end
