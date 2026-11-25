# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Dsl.Property do
  @moduledoc false
  @enforce_keys [:attribute, :predicate_iri]
  defstruct [
    :attribute,
    :predicate_iri,
    :datatype,
    :language,
    :language_column,
    :constant,
    :template,
    :__identifier__,
    :__spark_metadata__,
    term_type: :literal
  ]
end
