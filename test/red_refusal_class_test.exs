# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RedRefusalClassTest do
  @moduledoc """
  An inadmissible subject map must surface as the typed
  `:REFUSED_SENSITIVE_ATTRIBUTE_MATERIALIZATION` refusal, never as a raised
  `ArgumentError` nor as a generic `:REFUSED_READ_FAILED`.
  """

  use ExUnit.Case, async: false

  alias AshR2RML.Mapping.{Datatype, LogicalTable, ObjectMap, PredicateObjectMap, Resource, SubjectMap}
  alias AshR2RML.OBDA
  alias AshR2RML.OBDA.InMemory

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.RedRefusalClassTest.Thing
    end
  end

  defmodule Thing do
    use Ash.Resource,
      domain: AshR2RML.RedRefusalClassTest.Domain,
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(false)
    end

    actions do
      defaults([:read, create: [:name]])
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:name, :string, allow_nil?: false, public?: true)
    end
  end

  @name_pred "http://schema.org/name"
  @string "http://www.w3.org/2001/XMLSchema#string"

  defp ghost_subject_mapping do
    %Resource{
      ash_resource: Thing,
      logical_table: %LogicalTable{table_name: "things"},
      subject_map: %SubjectMap{strategy: :template, value: "urn:uuid:{ghost}", term_type: :iri},
      class_iris: [],
      predicate_object_maps: [
        %PredicateObjectMap{
          attribute: :name,
          predicate_iri: @name_pred,
          object_map: %ObjectMap{
            strategy: :column,
            value: "name",
            datatype: %Datatype{ash_type: Ash.Type.String, rdf_datatype: @string}
          }
        }
      ],
      identities: [[:id]],
      metadata: %{source: :red_refusal_class}
    }
  end

  setup do
    Thing
    |> Ash.Changeset.for_create(:create, %{name: "row"}, domain: Domain)
    |> Ash.create!(domain: Domain)

    :ok
  end

  test "H27 OBDA.query on an inadmissible subject map keeps the typed sensitive-attribute code" do
    sparql = "SELECT ?s WHERE { ?s <#{@name_pred}> ?o }"

    assert {:error, error} =
             OBDA.query([{Thing, ghost_subject_mapping()}], sparql, domain: Domain)

    assert error.code == :REFUSED_SENSITIVE_ATTRIBUTE_MATERIALIZATION
  end

  test "H40 materialize_many returns a typed refusal tuple instead of raising" do
    result =
      try do
        InMemory.materialize_many([{Thing, ghost_subject_mapping()}], domain: Domain)
      rescue
        e -> {:raised, e}
      end

    assert {:error, %{code: :REFUSED_SENSITIVE_ATTRIBUTE_MATERIALIZATION}} = result
  end
end
