# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.CloakEnclaveGuardTest do
  @moduledoc """
  An AshCloak-encrypted attribute never reaches rendered R2RML, OBDA triples, or subject,
  graph, object or join templates. The only lawful projection is an opaque
  `urn:sha256:<hex>` enclave pointer mapped as an ordinary constant IRI object.

  The fixture is a real `AshCloak` resource (ash_cloak is a test dep): `secret` becomes a
  decrypting calculation and ciphertext lives in the real attribute `encrypted_secret`.
  """

  use ExUnit.Case, async: false

  alias AshR2RML.Mapping.{
    Datatype,
    GraphMap,
    JoinCondition,
    LogicalTable,
    ObjectMap,
    PredicateObjectMap,
    ReferenceObjectMap,
    Resource,
    SubjectMap
  }

  alias AshR2RML.OBDA.InMemory
  alias AshR2RML.Security

  @plaintext "enclave-plaintext-canary"
  @xsd_string "http://www.w3.org/2001/XMLSchema#string"

  defmodule Vault do
    @moduledoc false
    def encrypt!(value) when is_binary(value), do: "enclave-cipher:" <> value
    def decrypt!("enclave-cipher:" <> value), do: value
  end

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.CloakEnclaveGuardTest.Vaulted
      resource AshR2RML.CloakEnclaveGuardTest.Sourced
    end
  end

  defmodule Vaulted do
    use Ash.Resource,
      domain: AshR2RML.CloakEnclaveGuardTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshCloak]

    ets do
      private?(false)
    end

    actions do
      defaults([:read, create: [:name, :secret]])
    end

    cloak do
      vault(AshR2RML.CloakEnclaveGuardTest.Vault)
      attributes([:secret])
      decrypt_by_default([:secret])
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:name, :string, allow_nil?: false, public?: true)
      attribute(:secret, :string, allow_nil?: false, public?: true)
    end
  end

  defmodule Sourced do
    use Ash.Resource,
      domain: AshR2RML.CloakEnclaveGuardTest.Domain,
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(false)
    end

    actions do
      defaults([:read, create: [:secret_note]])
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:secret_note, :string, public?: true, sensitive?: true, source: :db_secret)
    end
  end

  defp pointer, do: "urn:sha256:" <> Base.encode16(:crypto.hash(:sha256, @plaintext), case: :lower)

  defp string_datatype, do: %Datatype{ash_type: Ash.Type.String, rdf_datatype: @xsd_string}

  defp name_map do
    %PredicateObjectMap{
      attribute: :name,
      predicate_iri: "https://schema.org/name",
      object_map: %ObjectMap{strategy: :column, value: "name", datatype: string_datatype()}
    }
  end

  defp secret_map(strategy, value) do
    %PredicateObjectMap{
      attribute: :secret,
      predicate_iri: "https://schema.org/accessCode",
      object_map: %ObjectMap{strategy: strategy, value: value, datatype: string_datatype()}
    }
  end

  defp pointer_map do
    %PredicateObjectMap{
      attribute: nil,
      predicate_iri: "https://schema.org/url",
      object_map: %ObjectMap{strategy: :constant, value: pointer(), term_type: :iri}
    }
  end

  defp mapping(overrides \\ []) do
    base = %Resource{
      ash_resource: Vaulted,
      logical_table: %LogicalTable{table_name: "vaulted"},
      subject_map: %SubjectMap{
        strategy: :template,
        value: "urn:uuid:{id}",
        term_type: :iri
      },
      class_iris: ["https://schema.org/Thing"],
      predicate_object_maps: [name_map(), secret_map(:column, "secret"), pointer_map()],
      identities: [[:id]],
      metadata: %{}
    }

    struct!(base, overrides)
  end

  defp create! do
    Vaulted
    |> Ash.Changeset.for_create(:create, %{name: "Vaulted", secret: @plaintext}, domain: Domain)
    |> Ash.create!(domain: Domain)
  end

  defp external_turtle(mapping) do
    with {:ok, sanitized} <- {:ok, Security.sanitize_mapping(Vaulted, mapping)},
         :ok <- Security.check_protected_dependencies(Vaulted, sanitized) do
      AshR2RML.R2RML.render(sanitized)
    end
  end

  defp all_terms(graph) do
    graph
    |> RDF.Graph.triples()
    |> Enum.flat_map(fn {s, p, o} -> [to_string(s), to_string(p), to_string(o)] end)
  end

  test "fixture is a real AshCloak transform: secret is a calculation, ciphertext an attribute" do
    assert is_nil(Ash.Resource.Info.attribute(Vaulted, :secret))
    assert Ash.Resource.Info.calculation(Vaulted, :secret)
    assert Ash.Resource.Info.attribute(Vaulted, :encrypted_secret)
  end

  test "external R2RML: cloaked predicate map is not rendered; pointer is" do
    assert {:ok, turtle} = external_turtle(mapping())

    refute turtle =~ "https://schema.org/accessCode>"
    refute turtle =~ ~s(rr:column "secret")
    refute turtle =~ @plaintext
    refute turtle =~ "enclave-cipher"

    assert turtle =~ "https://schema.org/url"
    assert turtle =~ pointer()
    assert turtle =~ ~s(rr:column "name")
  end

  test "external R2RML: cloaked attribute in subject template is refused" do
    subject = %SubjectMap{
      strategy: :template,
      value: "urn:uuid:{secret}",
      term_type: :iri
    }

    assert {:error, %AshR2RML.Refusal{}} = external_turtle(mapping(subject_map: subject))
  end

  test "external R2RML: cloaked attribute in graph template is refused" do
    graph = %GraphMap{strategy: :template, value: "urn:uuid:{secret}"}

    assert {:error, %AshR2RML.Refusal{}} = external_turtle(mapping(graph_maps: [graph]))
  end

  test "external R2RML: cloaked attribute in object template is refused" do
    object = secret_map(:template, "urn:uuid:{secret}")

    assert {:error, %AshR2RML.Refusal{}} =
             external_turtle(mapping(predicate_object_maps: [name_map(), object]))
  end

  test "external R2RML: cloaked attribute as reference join child is refused" do
    ref = %ReferenceObjectMap{
      relationship: :peer,
      predicate_iri: "https://schema.org/knows",
      parent_resource: Vaulted,
      joins: [%JoinCondition{child: "secret", parent: "id"}]
    }

    assert {:error, %AshR2RML.Refusal{}} =
             external_turtle(mapping(reference_object_maps: [ref]))
  end

  test "external R2RML: cloaked attribute as reference join parent is refused" do
    ref = %ReferenceObjectMap{
      relationship: :peer,
      predicate_iri: "https://schema.org/knows",
      parent_resource: Vaulted,
      joins: [%JoinCondition{child: "id", parent: "secret"}]
    }

    assert {:error, %AshR2RML.Refusal{}} =
             external_turtle(mapping(reference_object_maps: [ref]))
  end

  test "OBDA triples: no plaintext or ciphertext term; pointer triple is present" do
    record = create!()

    assert {:ok, graph} = InMemory.materialize(Vaulted, mapping(), domain: Domain)

    terms = all_terms(graph)
    refute Enum.any?(terms, &String.contains?(&1, @plaintext))
    refute Enum.any?(terms, &String.contains?(&1, "enclave-cipher"))
    refute "https://schema.org/accessCode" in terms

    subject = RDF.iri("urn:uuid:#{record.id}")
    pointer_triple = {subject, RDF.iri("https://schema.org/url"), RDF.iri(pointer())}
    assert RDF.Graph.include?(graph, pointer_triple)
  end

  test "in-memory admission: cloaked attribute in subject template is refused, not rewritten" do
    subject = %SubjectMap{strategy: :template, value: "urn:uuid:{secret}", term_type: :iri}

    assert {:error, %AshR2RML.Refusal{code: :REFUSED_SENSITIVE_ATTRIBUTE_MATERIALIZATION, evidence: %{field: "secret"}}} =
             Security.admit_in_memory_mapping(Vaulted, mapping(subject_map: subject))
  end

  test "in-memory admission: blank-node subject template over a cloaked attribute is refused" do
    subject = %SubjectMap{strategy: :blank_node, value: "b_{secret}", term_type: :blank_node}

    assert {:error, %AshR2RML.Refusal{evidence: %{field: "secret", where: "subject map"}}} =
             Security.admit_in_memory_mapping(Vaulted, mapping(subject_map: subject))
  end

  test "in-memory admission: sensitive attribute with a source rename is caught in subject and graph maps" do
    sub = %SubjectMap{strategy: :template, value: "urn:uuid:{db_secret}", term_type: :iri}
    graph = %GraphMap{strategy: :template, value: "urn:uuid:{db_secret}"}
    base = %{mapping() | ash_resource: Sourced, predicate_object_maps: []}

    assert {:error, %AshR2RML.Refusal{evidence: %{field: "db_secret", where: "subject map"}}} =
             Security.admit_in_memory_mapping(Sourced, %{base | subject_map: sub})

    assert {:error, %AshR2RML.Refusal{evidence: %{field: "db_secret", where: "graph map"}}} =
             Security.admit_in_memory_mapping(Sourced, %{base | graph_maps: [graph]})

    by_name = %SubjectMap{strategy: :template, value: "urn:uuid:{secret_note}", term_type: :iri}

    assert {:error, %AshR2RML.Refusal{evidence: %{field: "secret_note"}}} =
             Security.admit_in_memory_mapping(Sourced, %{base | subject_map: by_name})
  end

  test "in-memory admission: public attribute subject is admitted unchanged" do
    assert {:ok, admitted} = Security.admit_in_memory_mapping(Vaulted, mapping())
    assert admitted.subject_map == mapping().subject_map
  end

  test "cloaked_attributes lists cloaked names and is empty for a resource without the extension" do
    assert Security.cloaked_attributes(Vaulted) == [:secret]
    assert Security.cloaked_attributes(Sourced) == []
  end

  test "OBDA triples: cloaked attribute in graph and object templates leaks no plaintext" do
    create!()

    graph_map = %GraphMap{strategy: :template, value: "urn:uuid:{secret}"}
    object = secret_map(:template, "urn:uuid:{secret}")

    overrides = [graph_maps: [graph_map], predicate_object_maps: [name_map(), object]]

    case InMemory.materialize(Vaulted, mapping(overrides), domain: Domain) do
      {:ok, graph} ->
        refute Enum.any?(all_terms(graph), &String.contains?(&1, @plaintext))

      {:error, %AshR2RML.Refusal{}} ->
        :ok
    end
  end

  test "OBDA SPARQL: querying the cloaked predicate yields no rows; pointer query does" do
    create!()

    assert {:ok, leak} =
             InMemory.query(
               Vaulted,
               mapping(),
               "SELECT ?v WHERE { ?s <https://schema.org/accessCode> ?v }",
               domain: Domain
             )

    assert leak.rows == []

    assert {:ok, lawful} =
             InMemory.query(
               Vaulted,
               mapping(),
               "SELECT ?v WHERE { ?s <https://schema.org/url> ?v }",
               domain: Domain
             )

    # the public ETS table accumulates rows across tests; every row carries the same pointer
    assert lawful.rows != []
    assert lawful.rows |> Enum.map(&to_string(&1["v"])) |> Enum.uniq() == [pointer()]
  end
end
