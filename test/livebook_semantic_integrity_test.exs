# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.LivebookSemanticIntegrityTest do
  use ExUnit.Case, async: true

  test "canonical semantic-integrity Livebook is an executable specification" do
    path = Path.expand("../documentation/how_to/semantic_integrity.livemd", __DIR__)

    assert {:ok, %{cells: 1, final: :all_green}} = AshR2RML.LivebookSpec.run(path)
  end
end