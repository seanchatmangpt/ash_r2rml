# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.R2RML.Turtle do
  @moduledoc """
  Turtle string-literal quoting for the R2RML renderer.
  """

  @doc """
  Quotes `value` (converted with `to_string/1`) as a Turtle string literal,
  escaping backslash, double quote, carriage return and newline.
  """
  @spec literal(term()) :: String.t()
  def literal(value) do
    escaped =
      value
      |> to_string()
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")
      |> String.replace("\r", "\\r")
      |> String.replace("\n", "\\n")

    "\"#{escaped}\""
  end
end
