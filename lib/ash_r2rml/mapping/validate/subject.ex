# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Mapping.Validate.Subject do
  @moduledoc """
  Validation rules for the logical table, RDF classes and subject map of a resource mapping.
  """

  import AshR2RML.Mapping.Validate.Shared

  alias AshR2RML.Mapping
  alias AshR2RML.Mapping.Validate.GraphMaps
  alias AshR2RML.Mapping.{LogicalTable, Resource, SubjectMap}
  alias AshR2RML.Refusal

  @doc "Refusals for the logical table: exactly one non-empty `table_name` or `sql_query`."
  @spec logical_table(Resource.t()) :: [Refusal.t()]
  def logical_table(%Resource{logical_table: %LogicalTable{} = logical} = resource) do
    case {logical.table_name, logical.sql_query} do
      {table, nil} when is_binary(table) and table != "" ->
        []

      {nil, query} when is_binary(query) and query != "" ->
        []

      _ ->
        [
          Refusal.new(
            :REFUSED_INVALID_LOGICAL_TABLE,
            resource.ash_resource,
            "mapping requires exactly one non-empty table_name or sql_query",
            %{logical_table: logical}
          )
        ]
    end
  end

  def logical_table(%Resource{} = resource) do
    [
      Refusal.new(
        :REFUSED_INVALID_LOGICAL_TABLE,
        resource.ash_resource,
        "mapping logical_table is missing"
      )
    ]
  end

  @doc "Refusals for the RDF class IRIs: at least one, all absolute."
  @spec classes(Resource.t()) :: [Refusal.t()]
  def classes(%Resource{class_iris: [], ash_resource: subject}) do
    [Refusal.new(:REFUSED_INVALID_CLASS_IRI, subject, "at least one RDF class IRI is required")]
  end

  def classes(%Resource{class_iris: iris, ash_resource: subject}) do
    iris
    |> Enum.reject(&absolute_iri?/1)
    |> Enum.map(&Refusal.new(:REFUSED_INVALID_CLASS_IRI, subject, "class IRI must be absolute", %{iri: &1}))
  end

  @doc "Refusals for the subject map."
  @spec subject(Resource.t()) :: [Refusal.t()]
  def subject(%Resource{subject_map: nil} = resource) do
    [
      Refusal.new(
        :REFUSED_MISSING_SUBJECT_MAP,
        resource.ash_resource,
        "RDF-emitting resource requires a subject map"
      )
    ]
  end

  def subject(%Resource{subject_map: %SubjectMap{} = subject} = resource) do
    []
    |> maybe_add(strategy(resource, subject))
    |> maybe_add(term_type(resource, subject))
    |> maybe_add(value(resource, subject))
    |> maybe_add(constant_iri(resource, subject))
    |> Kernel.++(columns(resource, subject))
    |> Kernel.++(GraphMaps.check(resource.ash_resource, subject.graph_maps))
    |> maybe_add(identity(resource, subject))
  end

  defp strategy(resource, subject) do
    if subject.strategy not in [:template, :column, :constant, :blank_node] do
      Refusal.new(:REFUSED_INVALID_TERM_MAP, resource.ash_resource, "unsupported subject strategy", %{
        strategy: subject.strategy
      })
    end
  end

  defp term_type(resource, subject) do
    if subject.term_type not in [:iri, :blank_node] do
      Refusal.new(:UNSUPPORTED_TERM_TYPE, resource.ash_resource, "unsupported subject term type", %{
        term_type: subject.term_type
      })
    end
  end

  defp value(resource, subject) do
    if not non_empty_string?(subject.value) do
      Refusal.new(
        :REFUSED_MISSING_SUBJECT_MAP,
        resource.ash_resource,
        "subject map value must be non-empty"
      )
    end
  end

  defp constant_iri(resource, subject) do
    if subject.strategy == :constant and subject.term_type == :iri and
         not absolute_iri?(subject.value) do
      Refusal.new(
        :REFUSED_MISSING_SUBJECT_MAP,
        resource.ash_resource,
        "constant IRI subject must be absolute",
        %{value: subject.value}
      )
    end
  end

  defp identity(resource, subject) do
    if not Mapping.stable_subject_identity?(resource) do
      Refusal.new(
        :REFUSED_NON_UNIQUE_SEMANTIC_IDENTITY,
        resource.ash_resource,
        "subject mapping is not proven by an admitted Ash/semantic identity",
        %{subject_map: subject, identities: resource.identities}
      )
    end
  end

  defp columns(resource, %SubjectMap{strategy: :template, value: template}) do
    template_refusals(
      resource,
      template,
      :REFUSED_MISSING_SUBJECT_MAP,
      resource.ash_resource,
      "subject template references columns absent from the admitted resource mapping"
    )
  end

  defp columns(resource, %SubjectMap{strategy: :column, value: column}) do
    if MapSet.member?(available_columns(resource), column) do
      []
    else
      [
        Refusal.new(
          :REFUSED_MISSING_SUBJECT_MAP,
          resource.ash_resource,
          "subject column is absent from the admitted resource mapping",
          %{column: column}
        )
      ]
    end
  end

  defp columns(resource, %SubjectMap{strategy: :blank_node, value: template})
       when is_binary(template) do
    template_refusals(
      resource,
      template,
      :REFUSED_MISSING_SUBJECT_MAP,
      resource.ash_resource,
      "blank-node subject template references columns absent from the admitted resource mapping"
    )
  end

  defp columns(_resource, _subject), do: []
end
