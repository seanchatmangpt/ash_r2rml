# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OBDAFieldPolicyFilterOracleTest do
  @moduledoc """
  A field_policy-gated attribute (admin only) must not act as a filter oracle for a
  non-admin: the visible result and stats must be independent of the hidden values.
  Real ETS-backed Ash resource, real policies, real actors; no doubles.
  """

  use ExUnit.Case, async: false

  alias AshR2RML.Mapping.{Datatype, LogicalTable, ObjectMap, PredicateObjectMap, Resource, SubjectMap}
  alias AshR2RML.OBDA

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.OBDAFieldPolicyFilterOracleTest.Scored
    end
  end

  defmodule Scored do
    use Ash.Resource,
      domain: AshR2RML.OBDAFieldPolicyFilterOracleTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      authorizers: [Ash.Policy.Authorizer]

    ets do
      private?(false)
    end

    actions do
      defaults([:read, :destroy, create: [:title, :secret]])
    end

    policies do
      policy always() do
        authorize_if(always())
      end
    end

    field_policies do
      field_policy :secret do
        authorize_if(actor_attribute_equals(:role, :admin))
      end

      field_policy :* do
        authorize_if(always())
      end
    end

    identities do
      identity(:by_title, [:title], pre_check_with: AshR2RML.OBDAFieldPolicyFilterOracleTest.Domain)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:title, :string, allow_nil?: false, public?: true)
      attribute(:secret, :integer, public?: true)
    end
  end

  @title_pred "https://example.org/title"
  @secret_pred "https://example.org/secret"
  @string "http://www.w3.org/2001/XMLSchema#string"
  @integer "http://www.w3.org/2001/XMLSchema#integer"

  @query "SELECT ?s WHERE { ?s <#{@title_pred}> ?id ; <#{@secret_pred}> ?x . FILTER(?x > 100) }"

  defp specs do
    poms = [
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
          datatype: %Datatype{ash_type: Ash.Type.Integer, rdf_datatype: @integer}
        }
      }
    ]

    [
      {Scored,
       %Resource{
         ash_resource: Scored,
         logical_table: %LogicalTable{table_name: "scored"},
         subject_map: %SubjectMap{
           strategy: :template,
           value: "https://example.org/scored/{title}",
           term_type: :iri
         },
         class_iris: ["https://example.org/Thing"],
         predicate_object_maps: poms,
         identities: [[:title]],
         metadata: %{source: :obda_field_policy_filter_oracle_test}
       }}
    ]
  end

  defp clear do
    Scored
    |> Ash.read!(authorize?: false, domain: Domain)
    |> Enum.each(&Ash.destroy!(&1, authorize?: false, domain: Domain))
  end

  defp load(secrets) do
    clear()

    for {secret, i} <- Enum.with_index(secrets, 1) do
      Scored
      |> Ash.Changeset.for_create(:create, %{title: "r#{i}", secret: secret}, domain: Domain)
      |> Ash.create!(authorize?: false, domain: Domain)
    end

    :ok
  end

  defp run(secrets, role) do
    load(secrets)
    assert {:ok, result} = OBDA.query(specs(), @query, domain: Domain, actor: %{role: role})
    result
  end

  defp visible(%OBDA.Result{} = r) do
    %{
      bindings: r.bindings |> Enum.map(&to_string(&1["s"])) |> Enum.sort(),
      rows_read: r.stats.rows_read,
      triples_emitted: r.stats.triples_emitted
    }
  end

  setup do
    clear()
    :ok
  end

  test "positive control: admin filter on the gated field distinguishes the datasets" do
    matching = run([50, 150, 250], :admin)
    none = run([1, 2, 3], :admin)

    assert length(matching.bindings) == 2
    assert none.bindings == []
  end

  test "non-admin: bindings are identical regardless of hidden secret values" do
    matching = run([50, 150, 250], :reader)
    none = run([1, 2, 3], :reader)

    assert visible(matching).bindings == visible(none).bindings
    assert matching.bindings == []
  end

  test "non-admin: stats.rows_read does not leak how many rows match the hidden filter" do
    matching = run([50, 150, 250], :reader)
    none = run([1, 2, 3], :reader)

    assert matching.stats.rows_read == none.stats.rows_read
  end

  test "non-admin: stats.triples_emitted does not leak how many rows match the hidden filter" do
    matching = run([50, 150, 250], :reader)
    none = run([1, 2, 3], :reader)

    assert matching.stats.triples_emitted == none.stats.triples_emitted
  end

  test "non-admin: full visible result is identical across datasets, including all-match" do
    a = visible(run([50, 150, 250], :reader))
    b = visible(run([1, 2, 3], :reader))
    c = visible(run([500, 600, 700], :reader))

    assert a == b
    assert b == c
  end
end
