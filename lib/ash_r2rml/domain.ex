# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Domain do
  @moduledoc """
  Spark extension for `Ash.Domain` that verifies the R2RML reference object maps
  of every mapped resource in the domain at compile time.

  Checks per `AshR2RML.Mapping.ReferenceObjectMap`:

    * the parent resource is a member of the domain
    * each join's parent column exists on the parent mapping
    * the parent has a subject map

      use Ash.Domain, extensions: [AshR2RML.Domain]
  """

  use Spark.Dsl.Extension,
    verifiers: [AshR2RML.Domain.Verifier]
end
