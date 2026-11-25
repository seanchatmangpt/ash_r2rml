# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Dsl.SparqlQuery do
  @moduledoc false
  @enforce_keys [:name]
  defstruct [:name, form: :select, select: [], where: [], __identifier__: nil, __spark_metadata__: nil]

  @type t :: %__MODULE__{
          name: atom(),
          form: :select | :construct | :ask | :describe,
          select: [atom()],
          where: term(),
          __identifier__: term(),
          __spark_metadata__: term()
        }
end
