# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OBDA.InMemorySensitiveCoverageTest do
  @moduledoc """
  Sensitive attributes used as subject-template fields, `:column` subject maps and
  join child columns are refused unless `allow_sensitive: true`.
  """

  use ExUnit.Case, async: false

  alias AshR2RML.Mapping.{JoinCondition, LogicalTable, ReferenceObjectMap, Resource, SubjectMap}
  alias AshR2RML.OBDA.InMemory
  alias AshR2RML.Refusal

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.OBDA.InMemorySensitiveCoverageTest.Person
    end
  end

  defmodule Person do
    use Ash.Resource,
      domain: AshR2RML.OBDA.InMemorySensitiveCoverageTest.Domain,
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(true)
    end

    actions do
      defaults([:read, create: [:name, :ssn, :internal_key, :boss_ssn]])
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:name, :string, allow_nil?: false, public?: true)
      attribute(:ssn, :string, allow_nil?: false, public?: true, sensitive?: true)
      attribute(:internal_key, :string, allow_nil?: false, public?: false)
      attribute(:boss_ssn, :string, public?: true, sensitive?: true)
    end
  end

  setup do
    Person
    |> Ash.Changeset.for_create(
      :create,
      %{name: "Ada", ssn: "123-45-6789", internal_key: "ik-1", boss_ssn: "987-65-4321"},
      domain: Domain
    )
    |> Ash.create!(domain: Domain)

    :ok
  end

  defp mapping(subject_map, refs \\ []) do
    %Resource{
      ash_resource: Person,
      logical_table: %LogicalTable{table_name: "people"},
      subject_map: subject_map,
      predicate_object_maps: [],
      reference_object_maps: refs,
      identities: [[:id]]
    }
  end

  defp assert_refused(result) do
    assert {:error, %Refusal{code: :REFUSED_SENSITIVE_ATTRIBUTE_MATERIALIZATION}} = result
    refute match?({:ok, _}, result)
  end

  test "sensitive attribute in subject template is refused" do
    m = mapping(%SubjectMap{strategy: :template, value: "urn:uuid:{ssn}"})
    assert_refused(InMemory.materialize(Person, m, domain: Domain))
  end

  test "sensitive attribute as :column subject map is refused" do
    m = mapping(%SubjectMap{strategy: :column, value: "ssn", term_type: :iri})
    assert_refused(InMemory.materialize(Person, m, domain: Domain))
  end

  test "sensitive attribute as join child column is refused" do
    ref = %ReferenceObjectMap{
      relationship: :boss,
      predicate_iri: "https://schema.org/parent",
      parent_resource: Person,
      joins: [%JoinCondition{child: "boss_ssn", parent: "ssn"}]
    }

    m = mapping(%SubjectMap{strategy: :template, value: "urn:uuid:{id}"}, [ref])
    assert_refused(InMemory.materialize(Person, m, domain: Domain))
  end

  test "non-sensitive subject template materializes" do
    m = mapping(%SubjectMap{strategy: :template, value: "urn:uuid:{id}"})
    assert {:ok, %RDF.Graph{}} = InMemory.materialize(Person, m, domain: Domain)
  end

  test "allow_sensitive: true admits the sensitive subject template" do
    m = mapping(%SubjectMap{strategy: :template, value: "urn:uuid:{ssn}"})

    assert {:ok, graph} = InMemory.materialize(Person, m, domain: Domain, allow_sensitive: true)
    assert %RDF.Graph{} = graph
  end
end
