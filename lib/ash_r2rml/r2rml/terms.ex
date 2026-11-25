# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.R2RML.Terms do
  @moduledoc """
  Term validation for the R2RML renderer.

  Checks that every constant IRI in a normalized `AshR2RML.Mapping.Bundle`
  can be written as a Turtle IRIREF, that no literal object map carries both a
  language and a datatype, and that every language is a well-formed Turtle
  LANGTAG. The first problem found is returned as a typed `AshR2RML.Refusal`;
  nothing is rewritten or repaired.
  """

  alias AshR2RML.Mapping.{Bundle, GraphMap, ObjectMap, Resource}
  alias AshR2RML.Refusal

  # C0 controls and space, IRIREF-forbidden characters, DEL and the C1 controls (U+0080-U+009F).
  @invalid_iri_chars ~r/[\x00-\x20<>"{}|^`\\\x7f\x{80}-\x{9f}]/u

  @langtag ~r/\A[A-Za-z]+(-[A-Za-z0-9]+)*\z/

  @doc """
  Returns `:ok`, or `{:error, refusal}` for the first invalid term in the bundle.
  """
  @spec validate(Bundle.t()) :: :ok | {:error, Refusal.t()}
  def validate(%Bundle{resources: resources}) do
    case Enum.flat_map(resources, &refusals/1) do
      [] -> :ok
      [first] -> {:error, first}
      [first | rest] -> {:error, %{first | evidence: Map.put(first.evidence, :additional_refusals, rest)}}
    end
  end

  @spec refusals(Resource.t()) :: [Refusal.t()]
  defp refusals(%Resource{} = resource) do
    iri_refusals =
      for {kind, iri} <- iris(resource), not valid_iri?(iri) do
        Refusal.new(
          :REFUSED_INVALID_TERM_MAP,
          resource.ash_resource,
          "#{kind} IRI is not serializable as an IRIREF",
          %{kind: kind, iri: iri}
        )
      end

    conflict_refusals =
      for property <- resource.predicate_object_maps, language_and_datatype?(property) do
        Refusal.new(
          :REFUSED_INVALID_TERM_MAP,
          {resource.ash_resource, property.attribute},
          "language and datatype are mutually exclusive on one literal object map"
        )
      end

    language_refusals =
      for property <- resource.predicate_object_maps, bad_language?(property) do
        Refusal.new(
          :REFUSED_INVALID_TERM_MAP,
          {resource.ash_resource, property.attribute},
          "language tag is not serializable as a Turtle LANGTAG",
          %{language: property.object_map.language}
        )
      end

    non_literal_refusals =
      for property <- resource.predicate_object_maps, typed_non_literal?(property) do
        Refusal.new(
          :REFUSED_INVALID_TERM_MAP,
          {resource.ash_resource, property.attribute},
          "datatype and language are only valid on literal object maps (R2RML 7.3)",
          %{term_type: property.object_map.term_type}
        )
      end

    unrenderable_refusals =
      for property <- resource.predicate_object_maps, not renderable_object?(property) do
        object = property.object_map

        Refusal.new(
          :REFUSED_INVALID_TERM_MAP,
          {resource.ash_resource, property.attribute},
          "object map strategy and term type cannot be rendered as R2RML (constant blank nodes are forbidden)",
          %{strategy: object.strategy, term_type: object.term_type}
        )
      end

    iri_refusals ++ conflict_refusals ++ language_refusals ++ non_literal_refusals ++ unrenderable_refusals
  end

  @term_types [:literal, :iri, :blank_node]

  # Mirrors the renderer's object term map clauses: a constant is only renderable as an IRI or literal
  # (R2RML 7.1: no constant blank nodes); template and column accept any known term type.
  defp renderable_object?(%{object_map: %ObjectMap{strategy: :constant, term_type: term_type}}),
    do: term_type in [:iri, :literal]

  defp renderable_object?(%{object_map: %ObjectMap{strategy: strategy, term_type: term_type}})
       when strategy in [:template, :column],
       do: term_type in @term_types

  defp renderable_object?(_), do: false

  defp typed_non_literal?(%{object_map: %ObjectMap{term_type: term_type, language: language, datatype: datatype}})
       when term_type != :literal,
       do: not is_nil(language) or not is_nil(datatype)

  defp typed_non_literal?(_), do: false

  # The renderer interpolates constant-literal languages unquoted (`"x"@tag`),
  # so a tag outside the Turtle LANGTAG shape would corrupt the document.
  defp bad_language?(%{object_map: %ObjectMap{strategy: :constant, language: language}}) when is_binary(language),
    do: not Regex.match?(@langtag, language)

  defp bad_language?(_), do: false

  defp iris(%Resource{} = resource) do
    subject = resource.subject_map

    Enum.map(resource.class_iris, &{:class, &1}) ++
      if(subject.strategy == :constant, do: [{:subject_constant, subject.value}], else: []) ++
      graph_iris(resource.graph_maps ++ subject.graph_maps) ++
      Enum.flat_map(resource.predicate_object_maps, &property_iris/1) ++
      Enum.flat_map(resource.reference_object_maps, &reference_iris/1)
  end

  defp reference_iris(ref) do
    [{:predicate, ref.predicate_iri}] ++
      if(ref.inverse_predicate, do: [{:inverse_predicate, ref.inverse_predicate}], else: []) ++
      graph_iris(ref.graph_maps)
  end

  defp language_and_datatype?(%{object_map: %ObjectMap{language: language, datatype: datatype}}),
    do: is_binary(language) and not is_nil(datatype)

  defp language_and_datatype?(_), do: false

  defp property_iris(property) do
    object = property.object_map

    [{:predicate, property.predicate_iri}] ++
      if(object.strategy == :constant and object.term_type == :iri, do: [{:object_constant, object.value}], else: []) ++
      case object.datatype do
        %{rdf_datatype: iri} when is_binary(iri) -> [{:datatype, iri}]
        _ -> []
      end ++
      graph_iris(property.graph_maps ++ object.graph_maps)
  end

  defp graph_iris(graph_maps) do
    for %GraphMap{strategy: :constant, value: value} <- graph_maps, do: {:graph, value}
  end

  defp valid_iri?(iri) when is_binary(iri) and iri != "",
    do: String.valid?(iri) and not Regex.match?(@invalid_iri_chars, iri)

  defp valid_iri?(_), do: false
end
