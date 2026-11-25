# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OBDARefusalEvidenceRedactionTest do
  @moduledoc """
  A policy-forbidden read must refuse with bounded, typed evidence (resource, error class):
  neither the Ash policy description nor stored sensitive values may reach the caller.
  Real ETS resource, real Ash policy authorizer, no doubles.
  """

  use ExUnit.Case, async: false

  alias AshR2RML.Mapping.{Datatype, LogicalTable, ObjectMap, PredicateObjectMap, Resource, SubjectMap}
  alias AshR2RML.OBDA.InMemory

  @policy_canary "POLICY-CANARY-XYZ"
  @secret_canary "SECRET-CANARY-XYZ"
  @title_pred "https://example.org/title"
  @secret_pred "https://example.org/secret"
  @string "http://www.w3.org/2001/XMLSchema#string"

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.OBDARefusalEvidenceRedactionTest.Vault
    end
  end

  defmodule Vault do
    use Ash.Resource,
      domain: AshR2RML.OBDARefusalEvidenceRedactionTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      authorizers: [Ash.Policy.Authorizer]

    ets do
      private?(false)
    end

    actions do
      defaults([:read, :destroy, create: [:title, :secret]])
    end

    policies do
      policy action_type(:read) do
        description("POLICY-CANARY-XYZ")
        authorize_if(actor_attribute_equals(:name, "admin"))
      end
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:title, :string, allow_nil?: false, public?: true)
      attribute(:secret, :string, public?: true, sensitive?: true)
    end
  end

  defp mapping do
    %Resource{
      ash_resource: Vault,
      logical_table: %LogicalTable{table_name: "vaults"},
      subject_map: %SubjectMap{strategy: :template, value: "https://example.org/vaults/{id}", term_type: :iri},
      class_iris: ["https://example.org/Vault"],
      predicate_object_maps: [
        %PredicateObjectMap{
          attribute: :title,
          predicate_iri: @title_pred,
          object_map: %ObjectMap{
            strategy: :column,
            value: "title",
            datatype: %Datatype{ash_type: Ash.Type.String, rdf_datatype: @string}
          }
        },
        %PredicateObjectMap{
          attribute: :secret,
          predicate_iri: @secret_pred,
          object_map: %ObjectMap{
            strategy: :column,
            value: "secret",
            datatype: %Datatype{ash_type: Ash.Type.String, rdf_datatype: @string}
          }
        }
      ],
      identities: [[:id]],
      metadata: %{source: :refusal_evidence_redaction_test}
    }
  end

  setup do
    Vault
    |> Ash.read!(authorize?: false, domain: Domain)
    |> Enum.each(&Ash.destroy!(&1, authorize?: false, domain: Domain))

    Vault
    |> Ash.Changeset.for_create(:create, %{title: "t1", secret: @secret_canary}, domain: Domain)
    |> Ash.create!(authorize?: false, domain: Domain)

    :ok
  end

  @select_secret "SELECT ?s ?v WHERE { ?s <#{@secret_pred}> ?v }"

  test "positive control: the secret is readable with an authorized actor and allow_sensitive" do
    assert {:ok, result} =
             AshR2RML.OBDA.query([{Vault, mapping()}], @select_secret,
               domain: Domain,
               actor: %{name: "admin"},
               allow_sensitive: true
             )

    assert inspect(result, limit: :infinity, printable_limit: :infinity) =~ @secret_canary
  end

  test "InMemory.query refusal omits policy text and sensitive values" do
    assert {:error, error} =
             InMemory.query(Vault, mapping(), @select_secret,
               actor: %{name: "mallory"},
               allow_sensitive: true,
               domain: Domain
             )

    rendered = inspect(error, limit: :infinity, printable_limit: :infinity)
    refute rendered =~ @policy_canary
    refute rendered =~ @secret_canary
    assert rendered =~ "Vault"
  end

  test "OBDA.query refusal omits policy text and sensitive values" do
    # Preflight may prune the forbidden resource (ok, empty) or refuse; either way the
    # caller-visible value must carry neither canary.
    result =
      AshR2RML.OBDA.query([{Vault, mapping()}], @select_secret,
        domain: Domain,
        actor: %{name: "mallory"},
        allow_sensitive: true
      )

    rendered = inspect(result, limit: :infinity, printable_limit: :infinity)
    refute rendered =~ @policy_canary
    refute rendered =~ @secret_canary
  end
end
