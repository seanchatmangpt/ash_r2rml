# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Formatter do
  @moduledoc """
  Spark.Formatter plugin helper for AshR2RML DSL sections (`r2rml` and `sparql`).
  """

  @doc "Returns the list of Spark extensions exported by AshR2RML."
  def extensions, do: [AshR2RML.Resource]

  @doc "Mix.Tasks.Format plugin callback"
  def features(_opts) do
    [extensions: [".ex", ".exs"]]
  end

  @doc "Mix.Tasks.Format plugin format callback"
  def format(contents, opts) do
    if Code.ensure_loaded?(Spark.Formatter) do
      opts_with_spark =
        Keyword.update(opts, :spark, [extensions: [AshR2RML.Resource]], fn spark ->
          Keyword.update(spark, :extensions, [AshR2RML.Resource], &[AshR2RML.Resource | &1])
        end)

      Spark.Formatter.format(contents, opts_with_spark)
    else
      contents
    end
  end
end
