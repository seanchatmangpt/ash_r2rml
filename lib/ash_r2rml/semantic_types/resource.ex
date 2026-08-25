# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.SemanticTypes.Dsl.Type do
  @moduledoc false
  @enforce_keys [:name, :iri]
  defstruct [
    :name,
    :iri,
    :selected_representation,
    :concept_scheme_iri,
    :quantity_kind,
    allowed_units: [],
    __identifier__: nil,
    __spark_metadata__: nil
  ]
end

defmodule AshR2RML.SemanticTypes.Resource do
  @moduledoc """
  Optional Spark extension for application-profile semantic type selections.

  Add it beside `AshR2RML.Resource`; it persists an admitted
  `AshR2RML.SemanticType.Plan` and never bypasses the semantic admission layer.
  """

  @semantic_type %Spark.Dsl.Entity{
    name: :type,
    args: [:name, :iri],
    target: AshR2RML.SemanticTypes.Dsl.Type,
    identifier: :name,
    schema: [
      name: [type: :atom, required: true],
      iri: [type: :string, required: true],
      selected_representation: [
        type: {:one_of, [:builtin, :new_type, :custom_type, :registry, :composite, :embedded, :jsonb, :resource]}
      ],
      concept_scheme_iri: [type: :string],
      quantity_kind: [type: :string],
      allowed_units: [type: {:list, :string}, default: []]
    ]
  }

  @section %Spark.Dsl.Section{
    name: :semantic_types,
    describe: "Public ontology value spaces and DfCM representation selections",
    entities: [@semantic_type]
  }

  use Spark.Dsl.Extension,
    sections: [@section],
    transformers: [AshR2RML.SemanticTypes.Resource.Persist],
    single_extension_kinds: [:ash_r2rml_semantic_types]
end

defmodule AshR2RML.SemanticTypes.Resource.Persist do
  @moduledoc false
  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer

  @impl true
  def transform(dsl) do
    entries =
      dsl
      |> Transformer.get_entities([:semantic_types])
      |> Enum.map(fn type ->
        %{
          name: type.name,
          iri: type.iri,
          selected_representation: type.selected_representation,
          concept_scheme_iri: type.concept_scheme_iri,
          quantity_kind: type.quantity_kind,
          allowed_units: type.allowed_units
        }
        |> Enum.reject(fn {_key, value} -> is_nil(value) or value == [] end)
        |> Map.new()
      end)

    case AshR2RML.SemanticTypes.plan(entries) do
      {:ok, plan} -> {:ok, Transformer.persist(dsl, :ash_r2rml_semantic_type_plan, plan)}
      {:error, refusals} -> {:error, Enum.map_join(refusals, "; ", &"#{&1.code}: #{&1.detail}")}
    end
  end
end

defmodule AshR2RML.SemanticTypes.Resource.Info do
  @moduledoc "Read-only Spark introspection for a resource's admitted semantic type plan."

  @spec plan(module()) :: AshR2RML.SemanticType.Plan.t() | nil
  def plan(resource) do
    Spark.Dsl.Extension.get_persisted(resource, :ash_r2rml_semantic_type_plan, nil)
  rescue
    _ -> nil
  end
end
