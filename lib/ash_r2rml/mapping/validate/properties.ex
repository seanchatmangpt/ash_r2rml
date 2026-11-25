# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Mapping.Validate.Properties do
  @moduledoc """
  Validation rules for predicate-object maps (attribute-backed properties).
  """

  import AshR2RML.Mapping.Validate.Shared

  alias AshR2RML.Mapping.Validate.{GraphMaps, Subject}
  alias AshR2RML.Mapping.{ObjectMap, Resource}
  alias AshR2RML.Refusal

  @doc "Refusals for every predicate-object map of the resource."
  @spec check(Resource.t()) :: [Refusal.t()]
  def check(resource), do: Enum.flat_map(resource.predicate_object_maps, &property(resource, &1))

  @doc "Refusals for repeated `(attribute, predicate)` predicate-object maps."
  @spec duplicates(Resource.t()) :: [Refusal.t()]
  def duplicates(resource) do
    resource.predicate_object_maps
    |> duplicate_keys(&{&1.attribute, &1.predicate_iri})
    |> Enum.map(fn {attribute, predicate} = key ->
      Refusal.new(
        :REFUSED_INVALID_TERM_MAP,
        {resource.ash_resource, attribute},
        "duplicate (attribute, predicate) predicate-object map",
        %{key: key, predicate_iri: predicate}
      )
    end)
  end

  defp property(resource, mapping) do
    object = mapping.object_map
    subject = {resource.ash_resource, mapping.attribute}

    []
    |> maybe_add(predicate(subject, mapping))
    |> maybe_add(term_type(subject, object))
    |> maybe_add(value(subject, object))
    |> maybe_add(language_datatype(subject, object))
    |> maybe_add(constant_iri(subject, object))
    |> Kernel.++(object_template(resource, mapping, object))
    |> Kernel.++(datatype(subject, object.datatype))
    |> Kernel.++(GraphMaps.check(subject, mapping.graph_maps ++ object.graph_maps))
  end

  defp predicate(subject, mapping) do
    if not absolute_iri?(mapping.predicate_iri) do
      Refusal.new(
        :REFUSED_RELATIONSHIP_WITHOUT_PREDICATE,
        subject,
        "predicate IRI must be absolute",
        %{predicate_iri: mapping.predicate_iri}
      )
    end
  end

  defp term_type(subject, object) do
    if object.term_type not in [:literal, :iri, :blank_node] do
      Refusal.new(:UNSUPPORTED_TERM_TYPE, subject, "unsupported object term type", %{
        term_type: object.term_type
      })
    end
  end

  defp value(subject, object) do
    if not non_empty_string?(object.value) do
      Refusal.new(:REFUSED_INVALID_TERM_MAP, subject, "object map value must be non-empty")
    end
  end

  defp language_datatype(subject, object) do
    if not is_nil(object.language) and not is_nil(object.datatype) do
      Refusal.new(
        :REFUSED_INVALID_TERM_MAP,
        subject,
        "language and datatype are mutually exclusive on one literal object map"
      )
    end
  end

  defp constant_iri(subject, object) do
    if object.strategy == :constant and object.term_type == :iri and
         not absolute_iri?(object.value) do
      Refusal.new(
        :REFUSED_INVALID_TERM_MAP,
        subject,
        "constant IRI object map must be an absolute IRI",
        %{value: object.value}
      )
    end
  end

  defp object_template(resource, mapping, %ObjectMap{strategy: :template, term_type: :iri, value: value} = object)
       when is_binary(value) do
    shape =
      Subject.template_shape_refusals(
        resource,
        value,
        {resource.ash_resource, mapping.attribute},
        "IRI object template must be an absolute IRI template with balanced braces"
      )

    shape ++ object_template(resource, mapping, %{object | term_type: :literal})
  end

  defp object_template(resource, mapping, %ObjectMap{strategy: :template, value: value})
       when is_binary(value) do
    template_refusals(
      resource,
      value,
      :REFUSED_INVALID_TERM_MAP,
      {resource.ash_resource, mapping.attribute},
      "object template references columns absent from the admitted resource mapping"
    )
  end

  defp object_template(_resource, _mapping, _object), do: []

  defp datatype(_subject, nil), do: []

  defp datatype(subject, %{rdf_datatype: iri}) when is_binary(iri) do
    if absolute_iri?(iri) do
      []
    else
      [
        Refusal.new(:REFUSED_UNMAPPED_DATATYPE, subject, "RDF datatype IRI must be absolute", %{
          datatype: iri
        })
      ]
    end
  end

  defp datatype(subject, value) do
    [
      Refusal.new(:REFUSED_UNMAPPED_DATATYPE, subject, "invalid datatype mapping", %{
        datatype: inspect(value)
      })
    ]
  end
end
