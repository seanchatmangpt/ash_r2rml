# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Formatter do
  @moduledoc """
  Spark.Formatter plugin helper for AshR2RML DSL sections (`r2rml` and `sparql`).
  """

  @doc "Returns the list of Spark extensions exported by AshR2RML."
  def extensions, do: [AshR2RML.Resource]
end
