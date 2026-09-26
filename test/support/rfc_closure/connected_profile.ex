# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Test.RFCClosure.ConnectedProfile do
  @moduledoc """
  Connected resource-graph profile (each resource belongs_to the previous one, 8 datatype
  attributes each), shared by the projection-identity benchmark and its regression-bound test.
  Same shape as `bench/compilation_and_rendering.exs`.
  """

  @xsd_string "http://www.w3.org/2001/XMLSchema#string"
  @xsd_decimal "http://www.w3.org/2001/XMLSchema#decimal"

  @spec profile(pos_integer()) :: map()
  def profile(resource_count) when resource_count > 0 do
    %{
      ontology_hash: "ontology:sha256:rfc-closure-#{resource_count}",
      profile_hash: "profile:sha256:rfc-closure-#{resource_count}",
      shacl_hash: "shacl:sha256:rfc-closure-#{resource_count}",
      resources: Enum.map(0..(resource_count - 1), &resource/1)
    }
  end

  defp resource(i) do
    %{
      iri: "https://bench.example/resource/R#{i}",
      class_iri: "https://bench.example/ontology/R#{i}",
      shape_iri: "https://bench.example/shapes/R#{i}Shape",
      module: "Bench.R#{i}",
      repo_module: "Bench.Repo",
      table: "bench_r#{i}",
      subject_template: "https://bench.example/id/r#{i}/{id}",
      identities: [%{name: :primary, keys: [:id], primary?: true}],
      attributes: [id_attribute()] ++ parent_attribute(i) ++ Enum.map(1..8, &datatype_attribute(i, &1)),
      relationships: parent_relationship(i)
    }
  end

  defp id_attribute do
    %{
      name: :id,
      column: "id",
      predicate_iri: "https://bench.example/ontology/id",
      datatype_iri: @xsd_string,
      ash_type: :uuid,
      postgres_type: "UUID",
      min_count: 1,
      max_count: 1,
      nullable: false,
      identity?: true
    }
  end

  defp parent_attribute(0), do: []

  defp parent_attribute(i) do
    [
      %{
        name: :parent_id,
        predicate_iri: "https://bench.example/ontology/R#{i}/parentId",
        datatype_iri: @xsd_string,
        ash_type: :uuid,
        postgres_type: "UUID",
        min_count: 0,
        max_count: 1
      }
    ]
  end

  defp datatype_attribute(i, j) do
    %{
      name: :"attr_#{j}",
      predicate_iri: "https://bench.example/ontology/R#{i}/attr#{j}",
      datatype_iri: if(rem(j, 2) == 0, do: @xsd_decimal, else: @xsd_string),
      min_count: 0,
      max_count: 1
    }
  end

  defp parent_relationship(0), do: []

  defp parent_relationship(i) do
    [
      %{
        name: :parent,
        predicate_iri: "https://bench.example/ontology/hasParent",
        source_class: "https://bench.example/ontology/R#{i}",
        target_class: "https://bench.example/ontology/R#{i - 1}",
        min_count: 0,
        max_count: 1,
        storage_strategy: :foreign_key,
        source_key: :parent_id,
        destination_key: :id
      }
    ]
  end
end
