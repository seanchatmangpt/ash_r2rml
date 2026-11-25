# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Dsl.Subject do
  @moduledoc false
  defstruct [:template, :column, :constant, :__identifier__, :__spark_metadata__, term_type: :iri]
end
