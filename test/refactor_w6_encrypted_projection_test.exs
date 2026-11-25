# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW6EncryptedProjectionTest do
  @moduledoc """
  `Security.check_encrypted_projection/2` refuses plaintext projection of an AshCloak
  attribute with `:REFUSED_ENCRYPTED_ATTRIBUTE_PROJECTION`, naming the mapped resource as
  subject and the offending field and position as evidence. A non-encrypted attribute and an
  opaque enclave pointer project fine.
  """

  use ExUnit.Case, async: false

  alias AshR2RML.Mapping.{
    Datatype,
    LogicalTable,
    ObjectMap,
    PredicateObjectMap,
    Resource,
    SubjectMap
  }

  alias AshR2RML.Security

  @xsd_string "http://www.w3.org/2001/XMLSchema#string"

  defmodule Vault do
    @moduledoc false
    def encrypt!(value) when is_binary(value), do: "w6-cipher:" <> value
    def decrypt!("w6-cipher:" <> value), do: value
  end

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.RefactorW6EncryptedProjectionTest.Card
    end
  end

  defmodule Card do
    use Ash.Resource,
      domain: AshR2RML.RefactorW6EncryptedProjectionTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshCloak]

    ets do
      private?(false)
    end

    actions do
      defaults([:read, create: [:name, :pin]])
    end

    cloak do
      vault(AshR2RML.RefactorW6EncryptedProjectionTest.Vault)
      attributes([:pin])
      decrypt_by_default([:pin])
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:name, :string, allow_nil?: false, public?: true)
      attribute(:pin, :string, allow_nil?: false, public?: true)
    end
  end

  defp datatype, do: %Datatype{ash_type: Ash.Type.String, rdf_datatype: @xsd_string}

  defp pom(attribute, column) do
    %PredicateObjectMap{
      attribute: attribute,
      predicate_iri: "http://schema.org/name",
      object_map: %ObjectMap{strategy: :column, value: column, datatype: datatype()}
    }
  end

  defp mapping(poms, subject_value \\ "urn:uuid:{id}") do
    %Resource{
      ash_resource: Card,
      logical_table: %LogicalTable{table_name: "cards"},
      subject_map: %SubjectMap{strategy: :template, value: subject_value, term_type: :iri},
      class_iris: ["http://schema.org/Thing"],
      predicate_object_maps: poms,
      identities: [[:id]],
      metadata: %{}
    }
  end

  test "positive control: a non-encrypted attribute projects" do
    assert :ok = Security.check_encrypted_projection(Card, mapping([pom(:name, "name")]))
  end

  test "plaintext projection of the encrypted attribute is refused with subject and field" do
    assert {:error, %AshR2RML.Refusal{} = refusal} =
             Security.check_encrypted_projection(Card, mapping([pom(:name, "name"), pom(:pin, "pin")]))

    assert refusal.code == :REFUSED_ENCRYPTED_ATTRIBUTE_PROJECTION
    assert refusal.subject == Card
    assert refusal.evidence == %{field: "pin", where: "property"}
  end

  test "encrypted attribute in the subject template is refused as a subject" do
    assert {:error, %AshR2RML.Refusal{} = refusal} =
             Security.check_encrypted_projection(Card, mapping([pom(:name, "name")], "http://schema.org/pin/{pin}"))

    assert refusal.code == :REFUSED_ENCRYPTED_ATTRIBUTE_PROJECTION
    assert refusal.subject == Card
    assert refusal.evidence == %{field: "pin", where: "subject"}
  end

  test "an opaque enclave pointer is admitted" do
    pointer = "urn:sha256:" <> Base.encode16(:crypto.hash(:sha256, "w6-pin"), case: :lower)

    pointer_pom = %PredicateObjectMap{
      attribute: nil,
      predicate_iri: "http://schema.org/url",
      object_map: %ObjectMap{strategy: :constant, value: pointer, term_type: :iri}
    }

    assert :ok = Security.check_encrypted_projection(Card, mapping([pom(:name, "name"), pointer_pom]))
  end
end
