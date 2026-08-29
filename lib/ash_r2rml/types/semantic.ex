# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Types.IRI do
  @moduledoc "Ash type for an RDF IRI value."
  use Ash.Type
  use AshR2RML.Type, semantic_kind: :iri, datatype_iri: nil, shacl_constraints: [node_kind: :iri]

  @impl Ash.Type
  def storage_type(_), do: :string

  @impl Ash.Type
  def constraints do
    [prefix: [type: :string, doc: "Optional required IRI prefix."]]
  end

  @impl Ash.Type
  def cast_input(nil, _), do: {:ok, nil}
  def cast_input(value, constraints) when is_binary(value), do: validate(value, constraints)
  def cast_input(_, _), do: {:error, "expected an absolute IRI string"}

  @impl Ash.Type
  def cast_stored(nil, _), do: {:ok, nil}
  def cast_stored(value, constraints) when is_binary(value), do: validate(value, constraints)
  def cast_stored(_, _), do: {:error, "stored IRI is not a string"}

  @impl Ash.Type
  def dump_to_native(nil, _), do: {:ok, nil}
  def dump_to_native(value, constraints) when is_binary(value), do: validate(value, constraints)
  def dump_to_native(_, _), do: :error

  @impl AshR2RML.Type
  def to_rdf(value) when is_binary(value), do: {:iri, value}
  def to_rdf(_), do: {:error, :invalid_iri}

  @impl AshR2RML.Type
  def from_rdf({:iri, value}), do: cast_input(value, [])
  def from_rdf(_), do: {:error, :rdf_term_kind_mismatch}

  defp validate(value, constraints) do
    with true <- AshR2RML.SemanticType.absolute_iri?(value),
         true <- prefix_ok?(value, constraints[:prefix]) do
      {:ok, value}
    else
      _ -> {:error, "expected an absolute IRI matching the configured prefix"}
    end
  end

  defp prefix_ok?(_value, nil), do: true
  defp prefix_ok?(value, prefix), do: String.starts_with?(value, prefix)
end

defmodule AshR2RML.Types.LangString do
  @moduledoc "RDF language-tagged string preserving lexical value and BCP47-like tag."
  use Ash.Type

  use AshR2RML.Type,
    semantic_kind: :literal,
    datatype_iri: "http://www.w3.org/1999/02/22-rdf-syntax-ns#langString"

  defstruct [:value, :language]

  @impl Ash.Type
  def storage_type(_), do: :map

  @impl Ash.Type
  def cast_input(nil, _), do: {:ok, nil}
  def cast_input(%__MODULE__{} = value, _), do: validate(value)
  def cast_input(%{value: value, language: language}, _), do: validate(%__MODULE__{value: value, language: language})

  def cast_input(%{"value" => value, "language" => language}, _),
    do: validate(%__MODULE__{value: value, language: language})

  def cast_input(_, _), do: {:error, "expected %{value: string, language: language_tag}"}

  @impl Ash.Type
  def cast_stored(value, constraints), do: cast_input(value, constraints)

  @impl Ash.Type
  def dump_to_native(nil, _), do: {:ok, nil}

  def dump_to_native(%__MODULE__{} = value, _) do
    with {:ok, value} <- validate(value) do
      {:ok, %{"value" => value.value, "language" => value.language}}
    end
  end

  def dump_to_native(_, _), do: :error

  @impl AshR2RML.Type
  def to_rdf(%__MODULE__{value: value, language: language}), do: {:lang_literal, value, language}
  def to_rdf(_), do: {:error, :invalid_lang_string}

  @impl AshR2RML.Type
  def from_rdf({:lang_literal, value, language}), do: validate(%__MODULE__{value: value, language: language})
  def from_rdf(_), do: {:error, :rdf_term_kind_mismatch}

  defp validate(%__MODULE__{value: value, language: language} = term)
       when is_binary(value) and is_binary(language) do
    if Regex.match?(~r/^[A-Za-z]{2,8}(?:-[A-Za-z0-9]{1,8})*$/, language) do
      {:ok, term}
    else
      {:error, "invalid language tag"}
    end
  end

  defp validate(_), do: {:error, "language-tagged value requires string value and language"}
end

defmodule AshR2RML.Types.Concept do
  @moduledoc "SKOS concept identity represented by canonical IRI plus optional scheme IRI."
  use Ash.Type

  use AshR2RML.Type,
    semantic_kind: :concept,
    datatype_iri: nil,
    class_iri: "http://www.w3.org/2004/02/skos/core#Concept",
    shacl_constraints: [node_kind: :iri, class: "http://www.w3.org/2004/02/skos/core#Concept"]

  defstruct [:iri, :scheme]

  @impl Ash.Type
  def storage_type(_), do: :map

  @impl Ash.Type
  def constraints do
    [scheme_iri: [type: :string, doc: "Optional required skos:ConceptScheme IRI."]]
  end

  @impl Ash.Type
  def cast_input(nil, _), do: {:ok, nil}

  def cast_input(value, constraints) when is_binary(value),
    do: validate(%__MODULE__{iri: value, scheme: constraints[:scheme_iri]}, constraints)

  def cast_input(%__MODULE__{} = value, constraints), do: validate(value, constraints)

  def cast_input(%{iri: iri} = value, constraints),
    do: validate(%__MODULE__{iri: iri, scheme: Map.get(value, :scheme)}, constraints)

  def cast_input(%{"iri" => iri} = value, constraints),
    do: validate(%__MODULE__{iri: iri, scheme: Map.get(value, "scheme")}, constraints)

  def cast_input(_, _), do: {:error, "expected a SKOS concept IRI or concept map"}

  @impl Ash.Type
  def cast_stored(value, constraints), do: cast_input(value, constraints)

  @impl Ash.Type
  def dump_to_native(nil, _), do: {:ok, nil}

  def dump_to_native(%__MODULE__{} = concept, constraints) do
    with {:ok, concept} <- validate(concept, constraints) do
      {:ok, %{"iri" => concept.iri, "scheme" => concept.scheme}}
    end
  end

  def dump_to_native(_, _), do: :error

  @impl Ash.Type
  def equal?(%__MODULE__{iri: left}, %__MODULE__{iri: right}), do: left == right
  def equal?(_, _), do: false

  @impl AshR2RML.Type
  def to_rdf(%__MODULE__{iri: iri}), do: {:iri, iri}
  def to_rdf(_), do: {:error, :invalid_concept}

  @impl AshR2RML.Type
  def from_rdf({:iri, iri}), do: cast_input(iri, [])
  def from_rdf(_), do: {:error, :rdf_term_kind_mismatch}

  defp validate(%__MODULE__{iri: iri, scheme: scheme} = concept, constraints) do
    required_scheme = constraints[:scheme_iri]

    cond do
      not AshR2RML.SemanticType.absolute_iri?(iri) ->
        {:error, "concept IRI must be absolute"}

      not is_nil(scheme) and not AshR2RML.SemanticType.absolute_iri?(scheme) ->
        {:error, "concept scheme IRI must be absolute"}

      required_scheme && scheme != required_scheme ->
        {:error, "concept is outside the admitted scheme"}

      true ->
        {:ok, %{concept | scheme: scheme || required_scheme}}
    end
  end
end

defmodule AshR2RML.Types.Quantity do
  @moduledoc "QUDT quantity value preserving numeric value, unit IRI, and optional quantity-kind IRI."
  use Ash.Type

  use AshR2RML.Type,
    semantic_kind: :value_object,
    datatype_iri: nil,
    class_iri: "http://qudt.org/schema/qudt/QuantityValue",
    shacl_constraints: [class: "http://qudt.org/schema/qudt/QuantityValue"]

  defstruct [:value, :unit, :quantity_kind]

  @impl Ash.Type
  def storage_type(_), do: :map

  @impl Ash.Type
  def constraints do
    [
      quantity_kind: [type: :string, doc: "Optional required QUDT quantity-kind IRI."],
      allowed_units: [type: {:list, :string}, default: [], doc: "Optional admitted QUDT unit IRIs."]
    ]
  end

  @impl Ash.Type
  def cast_input(nil, _), do: {:ok, nil}
  def cast_input(%__MODULE__{} = value, constraints), do: validate(value, constraints)

  def cast_input(%{value: value, unit: unit} = input, constraints),
    do: validate(%__MODULE__{value: value, unit: unit, quantity_kind: Map.get(input, :quantity_kind)}, constraints)

  def cast_input(%{"value" => value, "unit" => unit} = input, constraints),
    do: validate(%__MODULE__{value: value, unit: unit, quantity_kind: Map.get(input, "quantity_kind")}, constraints)

  def cast_input(_, _), do: {:error, "expected %{value: number, unit: absolute_iri}"}

  @impl Ash.Type
  def cast_stored(value, constraints), do: cast_input(value, constraints)

  @impl Ash.Type
  def dump_to_native(nil, _), do: {:ok, nil}

  def dump_to_native(%__MODULE__{} = quantity, constraints) do
    with {:ok, quantity} <- validate(quantity, constraints) do
      {:ok, %{"value" => quantity.value, "unit" => quantity.unit, "quantity_kind" => quantity.quantity_kind}}
    end
  end

  def dump_to_native(_, _), do: :error

  @impl AshR2RML.Type
  def to_rdf(%__MODULE__{} = quantity) do
    {:node,
     %{
       type: "http://qudt.org/schema/qudt/QuantityValue",
       numeric_value: quantity.value,
       unit: quantity.unit,
       quantity_kind: quantity.quantity_kind
     }}
  end

  def to_rdf(_), do: {:error, :invalid_quantity}

  @impl AshR2RML.Type
  def from_rdf({:node, %{unit: unit, numeric_value: value} = node}),
    do: cast_input(%{value: value, unit: unit, quantity_kind: Map.get(node, :quantity_kind)}, [])

  def from_rdf(_), do: {:error, :rdf_term_kind_mismatch}

  defp validate(%__MODULE__{} = quantity, constraints) do
    required_kind = constraints[:quantity_kind]
    allowed_units = constraints[:allowed_units] || []
    kind = quantity.quantity_kind || required_kind

    cond do
      not numeric?(quantity.value) ->
        {:error, "quantity value must be numeric"}

      not AshR2RML.SemanticType.absolute_iri?(quantity.unit) ->
        {:error, "quantity unit must be an absolute IRI"}

      kind && not AshR2RML.SemanticType.absolute_iri?(kind) ->
        {:error, "quantity kind must be an absolute IRI"}

      required_kind && kind != required_kind ->
        {:error, "quantity kind does not match the admitted kind"}

      allowed_units != [] and quantity.unit not in allowed_units ->
        {:error, "quantity unit is outside the admitted unit set"}

      true ->
        {:ok, %{quantity | quantity_kind: kind}}
    end
  end

  defp numeric?(value), do: is_number(value) or is_struct(value, Decimal)
end

defmodule AshR2RML.Types.TemporalInterval do
  @moduledoc "OWL-Time interval value with explicit beginning/end projections."
  use Ash.Type

  use AshR2RML.Type,
    semantic_kind: :value_object,
    datatype_iri: nil,
    class_iri: "http://www.w3.org/2006/time#Interval",
    shacl_constraints: [class: "http://www.w3.org/2006/time#Interval"]

  defstruct [:beginning, :ending]

  @impl Ash.Type
  def storage_type(_), do: :map

  @impl Ash.Type
  def cast_input(nil, _), do: {:ok, nil}
  def cast_input(%__MODULE__{} = value, _), do: validate(value)

  def cast_input(%{beginning: beginning, ending: ending}, _),
    do: validate(%__MODULE__{beginning: beginning, ending: ending})

  def cast_input(%{"beginning" => beginning, "ending" => ending}, _),
    do: validate(%__MODULE__{beginning: beginning, ending: ending})

  def cast_input(_, _), do: {:error, "expected interval beginning and ending"}

  @impl Ash.Type
  def cast_stored(value, constraints), do: cast_input(value, constraints)

  @impl Ash.Type
  def dump_to_native(nil, _), do: {:ok, nil}

  def dump_to_native(%__MODULE__{} = interval, _) do
    with {:ok, interval} <- validate(interval) do
      {:ok, %{"beginning" => interval.beginning, "ending" => interval.ending}}
    end
  end

  def dump_to_native(_, _), do: :error

  @impl AshR2RML.Type
  def to_rdf(%__MODULE__{} = interval),
    do: {:node, %{type: "http://www.w3.org/2006/time#Interval", beginning: interval.beginning, ending: interval.ending}}

  def to_rdf(_), do: {:error, :invalid_interval}

  @impl AshR2RML.Type
  def from_rdf({:node, %{beginning: beginning, ending: ending}}),
    do: validate(%__MODULE__{beginning: beginning, ending: ending})

  def from_rdf(_), do: {:error, :rdf_term_kind_mismatch}

  defp validate(%__MODULE__{beginning: nil}), do: {:error, "interval beginning is required"}
  defp validate(%__MODULE__{ending: nil}), do: {:error, "interval ending is required"}
  defp validate(%__MODULE__{} = interval), do: {:ok, interval}
end
