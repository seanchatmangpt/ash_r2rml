# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Dsl.Graph do
  @moduledoc false
  @enforce_keys [:iri]
  defstruct [:iri, :__identifier__, :__spark_metadata__, scope: :resource]
end
