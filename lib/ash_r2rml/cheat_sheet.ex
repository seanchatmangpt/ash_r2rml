# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.CheatSheet do
  @moduledoc """
  Generates cheat sheets and Markdown documentation for the `r2rml` Spark DSL extension.
  """

  @spec generate() :: String.t()
  def generate do
    Spark.CheatSheet.cheat_sheet(AshR2RML.Resource)
  end
end
