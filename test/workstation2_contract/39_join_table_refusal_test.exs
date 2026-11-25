# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.JoinTableRefusalTest do
  @moduledoc """
  A real `many_to_many` (join-table) relationship mapped through the DSL compiles to a
  bridge-aware mapping (`metadata.kind == :many_to_many`, `joins: []`); the in-memory
  OBDA backend cannot resolve the bridge rows and must answer with a typed refusal rather
  than silently dropping the relationship.
  """
  use ExUnit.Case, async: false

  alias AshR2RML.OBDA.InMemory
  alias AshR2RML.Refusal

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.WS2.JoinTableRefusalTest.Patient
      resource AshR2RML.WS2.JoinTableRefusalTest.Visit
      resource AshR2RML.WS2.JoinTableRefusalTest.Doctor
    end
  end

  defmodule Patient do
    use Ash.Resource,
      domain: AshR2RML.WS2.JoinTableRefusalTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    ets do
      private?(true)
    end

    attributes do
      uuid_primary_key :id
      attribute :name, :string, allow_nil?: false, public?: true
    end

    actions do
      defaults [:read, create: [:name]]
    end

    r2rml do
      table_name("ws2_patients")
      class("https://schema.org/Patient")

      subject do
        template("urn:uuid:{id}")
      end

      property(:name, "http://xmlns.com/foaf/0.1/name")
    end
  end

  defmodule Visit do
    use Ash.Resource,
      domain: AshR2RML.WS2.JoinTableRefusalTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    ets do
      private?(true)
    end

    attributes do
      uuid_primary_key :id
      attribute :doctor_id, :uuid, allow_nil?: false, public?: true
      attribute :patient_id, :uuid, allow_nil?: false, public?: true
    end

    actions do
      defaults [:read, create: [:doctor_id, :patient_id]]
    end

    r2rml do
      table_name("ws2_visits")
      class("https://schema.org/MedicalAppointment")

      subject do
        template("urn:uuid:{id}")
      end
    end
  end

  defmodule Doctor do
    use Ash.Resource,
      domain: AshR2RML.WS2.JoinTableRefusalTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    ets do
      private?(true)
    end

    attributes do
      uuid_primary_key :id
      attribute :name, :string, allow_nil?: false, public?: true
    end

    relationships do
      many_to_many :patients, AshR2RML.WS2.JoinTableRefusalTest.Patient do
        through AshR2RML.WS2.JoinTableRefusalTest.Visit
        source_attribute :id
        source_attribute_on_join_resource :doctor_id
        destination_attribute :id
        destination_attribute_on_join_resource :patient_id
        public? true
      end
    end

    actions do
      defaults [:read, create: [:name]]
    end

    r2rml do
      table_name("ws2_doctors")
      class("https://schema.org/Physician")

      subject do
        template("urn:uuid:{id}")
      end

      property(:name, "http://xmlns.com/foaf/0.1/name")
      reference(:patients, "http://xmlns.com/foaf/0.1/knows")
    end
  end

  test "many_to_many compiles as a bridge mapping, then in-memory materialization refuses typed" do
    mapping = AshR2RML.Resource.Info.mapping!(Doctor)
    assert [%{metadata: %{kind: :many_to_many}, joins: []}] = mapping.reference_object_maps
    assert {:ok, _bundle} = AshR2RML.compile(Doctor)

    Doctor
    |> Ash.Changeset.for_create(:create, %{name: "Who"}, domain: Domain)
    |> Ash.create!(domain: Domain)

    assert {:error, %Refusal{code: :REFUSED_UNSUPPORTED_SPARQL_FEATURE, subject: Patient} = refusal} =
             InMemory.materialize(Doctor, mapping, domain: Domain)

    assert refusal.detail =~ "join_table"
    assert refusal.evidence.relationship == :patients
  end
end
