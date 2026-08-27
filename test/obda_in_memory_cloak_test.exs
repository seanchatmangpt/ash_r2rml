# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OBDA.InMemoryCloakTest do
  @moduledoc """
  Real regression for R2RML-109.

  `AshCloak` replaces an encrypted Ash attribute with a sensitive calculation under the
  original public name and stores ciphertext in `encrypted_<name>`. With
  `decrypt_by_default`, a plain `Ash.read!/2` loads that calculation automatically. This
  suite proves the dangerous precondition first, then proves InMemory's admission boundary
  removes the derived field before RDF materialization and SPARQL execution.
  """

  use ExUnit.Case, async: false

  alias AshR2RML.Mapping.{Datatype, LogicalTable, ObjectMap, PredicateObjectMap, Resource, SubjectMap}
  alias AshR2RML.OBDA.InMemory
  alias AshR2RML.Security

  defmodule Vault do
    @moduledoc false

    def encrypt!(value) when is_binary(value), do: "ash-r2rml-cipher:" <> value
    def decrypt!("ash-r2rml-cipher:" <> value), do: value
  end

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.OBDA.InMemoryCloakTest.SecretRecord
    end
  end

  defmodule SecretRecord do
    use Ash.Resource,
      domain: AshR2RML.OBDA.InMemoryCloakTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshCloak]

    ets do
      private?(true)
    end

    actions do
      defaults([:read, create: [:name, :secret]])
    end

    cloak do
      vault(AshR2RML.OBDA.InMemoryCloakTest.Vault)
      attributes([:secret])
      decrypt_by_default([:secret])
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:name, :string, allow_nil?: false, public?: true)
      attribute(:secret, :string, allow_nil?: false, public?: true)
    end
  end

  defp mapping do
    %Resource{
      ash_resource: SecretRecord,
      logical_table: %LogicalTable{table_name: "secret_records"},
      subject_map: %SubjectMap{
        strategy: :template,
        value: "https://example.org/records/{id}",
        term_type: :iri
      },
      class_iris: ["https://example.org/SecretRecord"],
      predicate_object_maps: [
        %PredicateObjectMap{
          attribute: :name,
          predicate_iri: "https://example.org/name",
          object_map: %ObjectMap{
            strategy: :column,
            value: "name",
            datatype: %Datatype{
              ash_type: Ash.Type.String,
              rdf_datatype: "http://www.w3.org/2001/XMLSchema#string"
            }
          }
        },
        %PredicateObjectMap{
          attribute: :secret,
          predicate_iri: "https://example.org/secret",
          object_map: %ObjectMap{
            strategy: :column,
            value: "secret",
            datatype: %Datatype{
              ash_type: Ash.Type.String,
              rdf_datatype: "http://www.w3.org/2001/XMLSchema#string"
            }
          }
        }
      ],
      identities: [[:id]],
      metadata: %{source: :r2rml_109_regression}
    }
  end

  defp create_secret! do
    secret = "plaintext-must-never-enter-rdf"

    record =
      SecretRecord
      |> Ash.Changeset.for_create(
        :create,
        %{name: "Cloaked Record", secret: secret},
        domain: Domain
      )
      |> Ash.create!(domain: Domain)

    {record, secret}
  end

  test "real AshCloak decrypt_by_default makes plaintext observable to an ordinary Ash read" do
    {record, secret} = create_secret!()
    read_record = Enum.find(Ash.read!(SecretRecord, domain: Domain), &(&1.id == record.id))

    assert read_record.secret == secret
    assert is_nil(Ash.Resource.Info.attribute(SecretRecord, :secret))
    assert Ash.Resource.Info.calculation(SecretRecord, :secret)
    assert Ash.Resource.Info.attribute(SecretRecord, :encrypted_secret)
  end

  test "security admission records and strips the transformed non-attribute mapping" do
    sanitized = Security.sanitize_in_memory_mapping(SecretRecord, mapping())

    assert sanitized.metadata.in_memory_non_attribute_excluded_attributes == [:secret]
    assert Enum.any?(sanitized.predicate_object_maps, &(&1.attribute == :name))
    refute Enum.any?(sanitized.predicate_object_maps, &(&1.attribute == :secret))
    assert Security.non_attribute_mapped_fields(SecretRecord, mapping()) == [:secret]
  end

  test "InMemory materialization and SPARQL never publish decrypt_by_default plaintext" do
    {record, secret} = create_secret!()

    assert {:ok, graph} = InMemory.materialize(SecretRecord, mapping(), domain: Domain)

    subject = RDF.iri("https://example.org/records/#{record.id}")
    name_predicate = RDF.iri("https://example.org/name")
    secret_predicate = RDF.iri("https://example.org/secret")

    assert RDF.Graph.include?(graph, {subject, name_predicate, RDF.literal("Cloaked Record")})

    refute Enum.any?(RDF.Graph.triples(graph), fn {_subject, predicate, object} ->
             predicate == secret_predicate or to_string(object) == secret
           end)

    assert {:ok, observation} =
             InMemory.query(
               SecretRecord,
               mapping(),
               "SELECT ?secret WHERE { ?s <https://example.org/secret> ?secret }",
               domain: Domain
             )

    assert observation.rows == []
  end
end
