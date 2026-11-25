# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.R2RML.Terms do
  @moduledoc """
  Term validation for the R2RML renderer.

  Checks that every constant IRI in a normalized `AshR2RML.Mapping.Bundle`
  can be written as a Turtle IRIREF, and that no literal object map carries
  both a language and a datatype, and that every language is a well-formed
  Turtle LANGTAG. The first problem found is returned as a
  typed `AshR2RML.Refusal`; nothing is rewritten or repaired.
  """

  alias AshR2RML.Mapping.{Bundle, GraphMap, ObjectMap, Resource}
  alias AshR2RML.Refusal

  @invalid_iri_chars ~r/[\x00-\x20<>"{}|^`\\\x7f]/

  @langtag ~r/\A[A-Za-z]+(-[A-Za-z0-9]+)*\z/

  @doc """
  Returns `:ok`, or `{:error, refusal}` for the first invalid term in the bundle.
  """
  @spec validate(Bundle.t()) :: :ok | {:error, Refusal.t()}
  def validate(%Bundle{resources: resources}) do
    case Enum.flat_map(resources, &refusals/1) do
      [] -> :ok
      [first | _] -> {:error, first}
    end
  end

  @spec refusals(Resource.t()) :: [Refusal.t()]
  defp refusals(%Resource{} = resource) do
    iri_refusals =
      for {kind, iri} <- iris(resource), not valid_iri?(iri) do
        Refusal.new(:REFUSED_INVALID_TERM_MAP, resource.ash_resource, "#{kind} IRI is not serializable as an IRIREF", %{
          kind: kind,
          iri: iri
        })
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

    iri_refusals ++ conflict_refusals ++ language_refusals
  end

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

  defp valid_iri?(iri), do: is_binary(iri) and not Regex.match?(@invalid_iri_chars, iri)
end
