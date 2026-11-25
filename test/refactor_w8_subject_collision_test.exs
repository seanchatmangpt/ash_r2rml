# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW8SubjectCollisionTest do
  @moduledoc """
  Distinct string keys that a type normalizes (trim) must refuse on `Subject.to_iri/2`
  instead of collapsing onto one IRI.
  """
  use ExUnit.Case, async: true

  alias AshR2RML.Mapping.{LogicalTable, Resource, SubjectMap}
  alias AshR2RML.{Refusal, Subject}

  defmodule Dom do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.RefactorW8SubjectCollisionTest.Keyed
    end
  end

  defmodule Keyed do
    use Ash.Resource, domain: AshR2RML.RefactorW8SubjectCollisionTest.Dom, data_layer: Ash.DataLayer.Ets

    ets do
      private? false
    end

    actions do
      defaults [:read]
    end

    attributes do
      uuid_primary_key :id
      attribute :code, :string, public?: true
      attribute :region, :string, public?: true
      attribute :num, :integer, public?: true
    end
  end

  @uuid "0b1f6c3e-8d52-4a37-9c11-6a2e5d0f7b44"

  defp mapping(template) do
    %Resource{
      ash_resource: Keyed,
      logical_table: %LogicalTable{table_name: "keyed"},
      subject_map: %SubjectMap{strategy: :template, value: "http://schema.org/" <> template}
    }
  end

  defp refused(result), do: assert({:error, %Refusal{code: :REFUSED_INVALID_SUBJECT_IRI}} = result)

  test "exact string key renders; whitespace-normalized variants refuse" do
    m = mapping("t/{code}")
    assert Subject.to_iri(m, %{code: "a"}) == {:ok, "http://schema.org/t/a"}
    refused(Subject.to_iri(m, %{code: " a"}))
    refused(Subject.to_iri(m, %{code: "a "}))
  end

  test "composite keys are checked per field" do
    m = mapping("t/{code}/{region}")
    assert Subject.to_iri(m, %{code: "a", region: "eu"}) == {:ok, "http://schema.org/t/a/eu"}
    refused(Subject.to_iri(m, %{code: "a", region: "eu "}))
    refused(Subject.to_iri(m, %{code: " a", region: "eu"}))
  end

  test "integer and uuid controls are unchanged" do
    assert Subject.to_iri(mapping("n/{num}"), %{num: "42"}) == {:ok, "http://schema.org/n/42"}
    assert Subject.to_iri(mapping("n/{num}"), %{num: 42}) == {:ok, "http://schema.org/n/42"}
    assert Subject.to_iri(mapping("u/{id}"), %{id: @uuid}) == {:ok, "http://schema.org/u/" <> @uuid}
  end

  test "refusal names the field and both values" do
    {:error, %Refusal{evidence: evidence}} = Subject.to_iri(mapping("t/{code}"), %{code: "a "})
    assert %{field: :code, input: "a ", normalized: "a"} = evidence
  end
end
