# SPDX-FileCopyrightText: 2026 ash_r2ml contributors <https://github.com/seanchatmangpt/ash_r2ml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2ml.Mapping do
  @moduledoc "Canonical, data-layer-neutral semantic mapping IR for an Ash resource."

  @enforce_keys [:resource, :class_iri, :subject_template, :logical_table]
  defstruct [
    :resource,
    :class_iri,
    :subject_template,
    :logical_table,
    :graph_iri,
    attributes: [],
    relationships: []
  ]

  @type logical_table :: {:table, String.t()} | {:sql_query, String.t()}
  @type t :: %__MODULE__{
          resource: module(),
          class_iri: String.t(),
          subject_template: String.t(),
          logical_table: logical_table(),
          graph_iri: String.t() | nil,
          attributes: [AshR2ml.AttributeMapping.t()],
          relationships: [AshR2ml.RelationshipMapping.t()]
        }
end

defmodule AshR2ml.AttributeMapping do
  @moduledoc "Relational-column to RDF-predicate projection."

  @enforce_keys [:attribute, :column, :predicate_iri]
  defstruct [:attribute, :column, :predicate_iri, :datatype_iri]

  @type t :: %__MODULE__{
          attribute: atom(),
          column: String.t(),
          predicate_iri: String.t(),
          datatype_iri: String.t() | nil
        }
end

defmodule AshR2ml.RelationshipMapping do
  @moduledoc "Referencing-object-map projection derived from an Ash relationship."

  @enforce_keys [
    :relationship,
    :predicate_iri,
    :destination,
    :child_column,
    :parent_column
  ]
  defstruct [
    :relationship,
    :predicate_iri,
    :destination,
    :child_column,
    :parent_column
  ]

  @type t :: %__MODULE__{
          relationship: atom(),
          predicate_iri: String.t(),
          destination: module(),
          child_column: String.t(),
          parent_column: String.t()
        }
end
