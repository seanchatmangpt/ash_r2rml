# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RedObdaRegexErrorTest do
  @moduledoc """
  H04: no compiled regex lives in a module attribute. H05: `OBDA.query/3` has one error struct.
  """
  use ExUnit.Case, async: true

  alias AshR2RML.Error
  alias AshR2RML.OBDA
  alias AshR2RML.Refusal

  @root Path.expand("..", __DIR__)
  @attr_regex ~r/^\s*@[a-z_]+\s+(?:\[\s*)?~r[\/{(|"']/m

  defp attr_regex_hits(rel) do
    @root |> Path.join(rel) |> File.read!() |> then(&Regex.scan(@attr_regex, &1))
  end

  test "H04 obda.ex stores no compiled regex in a module attribute" do
    assert attr_regex_hits("lib/ash_r2rml/obda.ex") == []
  end

  test "H04 iri_template.ex stores no compiled regex in a module attribute" do
    path = Path.join(@root, "lib/ash_r2rml/obda_in_memory/iri_template.ex")

    path =
      if File.exists?(path),
        do: path,
        else: Path.wildcard(Path.join(@root, "lib/**/iri_template.ex")) |> List.first()

    assert is_binary(path)
    assert Regex.scan(@attr_regex, File.read!(path)) == []
  end

  test "H05 a bound refusal leaves query/3 as %Error{}" do
    assert {:error, error} = OBDA.query([], "SELECT * WHERE { ?s ?p ?o }", max_rows: -1)
    assert %Error{} = error
    assert is_binary(Exception.message(error))
  end

  test "H05 normalize_result converts a returned %Refusal{} into %Error{}" do
    refusal = Refusal.new(:REFUSED_READ_FAILED, "subject", "detail", %{})
    assert {:error, %Error{}} = OBDA.normalize_result({:error, refusal})
  end

  test "H05 normalize_result converts a refusal list head into %Error{}" do
    refusal = Refusal.new(:REFUSED_READ_FAILED, "subject", "detail", %{})
    assert {:error, %Error{}} = OBDA.normalize_result({:error, [refusal]})
  end
end
