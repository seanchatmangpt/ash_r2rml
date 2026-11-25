# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.FollowupJoinChildSensitivityTest do
  @moduledoc """
  A `sensitive?: true` attribute with a `source` rename must be refused as a reference-join
  child column whether the join names it by attribute name or by storage column.
  Real ETS-backed resource, real `AshR2RML.OBDA.InMemory.query/4`.
  """

  use ExUnit.Case, async: false

  alias AshR2RML.Followup.{Domain, Renamed}
  alias AshR2RML.Mapping.{Datatype, JoinCondition, LogicalTable, ObjectMap, PredicateObjectMap, ReferenceObjectMap}
  alias AshR2RML.Mapping.{Resource, SubjectMap}
  alias AshR2RML.OBDA.InMemory

  @name_pred "https://schema.org/name"
  @parent_pred "https://schema.org/parent"
  @string "http://www.w3.org/2001/XMLSchema#string"
  @select "SELECT ?s ?o WHERE { ?s <#{@name_pred}> ?o }"

  setup do
    Renamed
    |> Ash.read!(domain: Domain)
    |> Enum.each(&Ash.destroy!(&1, domain: Domain))

    Renamed
    |> Ash.Changeset.for_create(:create, %{name: "Ada", ssn: "123-45-6789", boss_code: "b-1"}, domain: Domain)
    |> Ash.create!(domain: Domain)

    :ok
  end

  defp mapping(child) do
    ref = %ReferenceObjectMap{
      relationship: :boss,
      predicate_iri: @parent_pred,
      parent_resource: Renamed,
      joins: [%JoinCondition{child: child, parent: "id"}]
    }

    %Resource{
      ash_resource: Renamed,
      logical_table: %LogicalTable{table_name: "renamed"},
      subject_map: %SubjectMap{strategy: :template, value: "urn:uuid:{id}", term_type: :iri},
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
      reference_object_maps: [ref],
      identities: [[:id]]
    }
  end

  defp assert_sensitive_refusal(result) do
    assert {:error, %{code: :REFUSED_SENSITIVE_ATTRIBUTE_MATERIALIZATION}} = result
  end

  test "join child named by the source rename of a sensitive attribute is refused" do
    assert_sensitive_refusal(InMemory.query(Renamed, mapping("db_ssn"), @select, domain: Domain))
  end

  test "join child named by the attribute name of a sensitive attribute is refused" do
    assert_sensitive_refusal(InMemory.query(Renamed, mapping("ssn"), @select, domain: Domain))
  end

  test "join child on a non-sensitive attribute is admitted (positive control)" do
    assert {:ok, observation} = InMemory.query(Renamed, mapping("boss_code"), @select, domain: Domain)
    assert [%{"o" => name}] = observation.rows
    assert to_string(name) =~ "Ada"
  end

  test "allow_sensitive: true admits the renamed sensitive join child" do
    assert {:ok, _observation} =
             InMemory.query(Renamed, mapping("db_ssn"), @select, domain: Domain, allow_sensitive: true)
  end
end
