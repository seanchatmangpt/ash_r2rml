# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Dsl.Reference do
  @moduledoc false
  @enforce_keys [:relationship, :predicate_iri]
  defstruct [
    :relationship,
    :predicate_iri,
    :inverse_predicate,
    :guard_class,
    :__identifier__,
    :__spark_metadata__,
    direction: :outgoing
  ]
end
