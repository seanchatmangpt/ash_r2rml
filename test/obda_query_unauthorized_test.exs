# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OBDAQueryUnauthorizedTest do
  @moduledoc """
  Authorization, field-policy, sensitive-attribute and tenant isolation asserted through the
  public `AshR2RML.OBDA.query/3` envelope. Real ETS-backed Ash resources with real
  `Ash.Policy.Authorizer` policies and real actors; no doubles.

  Observed contract pinned here: an actor that `Ash.can?/3` (maybe_is) denies for a
  resource is *pruned* -- `{:ok, result}` with zero rows and
  `stats.resources_pruned_by_policy == 1` -- not an error tuple.
  """

  use ExUnit.Case, async: false

  alias AshR2RML.Mapping.{Datatype, LogicalTable, ObjectMap, PredicateObjectMap, Resource, SubjectMap}
  alias AshR2RML.OBDA

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.OBDAQueryUnauthorizedTest.Gated
      resource AshR2RML.OBDAQueryUnauthorizedTest.Fielded
      resource AshR2RML.OBDAQueryUnauthorizedTest.Sensitive
      resource AshR2RML.OBDAQueryUnauthorizedTest.Tenanted
    end
  end

  defmodule Gated do
    use Ash.Resource,
      domain: AshR2RML.OBDAQueryUnauthorizedTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      authorizers: [Ash.Policy.Authorizer]

    ets do
      private?(false)
    end

    actions do
      defaults([:read, :destroy, create: [:title]])
    end

    policies do
      policy action_type(:read) do
        authorize_if(actor_attribute_equals(:role, :reader))
      end
    end

    identities do
      identity(:by_title, [:title], pre_check_with: AshR2RML.OBDAQueryUnauthorizedTest.Domain)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:title, :string, allow_nil?: false, public?: true)
    end
  end

  defmodule Fielded do
    use Ash.Resource,
      domain: AshR2RML.OBDAQueryUnauthorizedTest.Domain,
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
      identity(:by_title, [:title], pre_check_with: AshR2RML.OBDAQueryUnauthorizedTest.Domain)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:title, :string, allow_nil?: false, public?: true)
      attribute(:secret, :string, public?: true)
    end
  end

  defmodule Sensitive do
    use Ash.Resource,
      domain: AshR2RML.OBDAQueryUnauthorizedTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      authorizers: [Ash.Policy.Authorizer]

    ets do
      private?(false)
    end

    actions do
      defaults([:read, :destroy, create: [:title, :token]])
    end

    policies do
      policy always() do
        authorize_if(always())
      end
    end

    identities do
      identity(:by_title, [:title], pre_check_with: AshR2RML.OBDAQueryUnauthorizedTest.Domain)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:title, :string, allow_nil?: false, public?: true)
      attribute(:token, :string, public?: true, sensitive?: true)
    end
  end

  defmodule Tenanted do
    use Ash.Resource,
      domain: AshR2RML.OBDAQueryUnauthorizedTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      authorizers: [Ash.Policy.Authorizer]

    ets do
      private?(false)
    end

    multitenancy do
      strategy(:attribute)
      attribute(:tenant_id)
    end

    actions do
      defaults([:read, :destroy, create: [:title]])
    end

    policies do
      policy always() do
        authorize_if(always())
      end
    end

    identities do
      identity(:by_title, [:title], pre_check_with: AshR2RML.OBDAQueryUnauthorizedTest.Domain)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:title, :string, allow_nil?: false, public?: true)
      attribute(:tenant_id, :string, allow_nil?: false, public?: true)
    end
  end

  @title_pred "https://example.org/title"
  @secret_pred "https://example.org/secret"
  @token_pred "https://example.org/token"
  @string "http://www.w3.org/2001/XMLSchema#string"

  defp pom(attribute, predicate) do
    %PredicateObjectMap{
      attribute: attribute,
      predicate_iri: predicate,
      object_map: %ObjectMap{
        strategy: :column,
        value: Atom.to_string(attribute),
        datatype: %Datatype{ash_type: Ash.Type.String, rdf_datatype: @string}
      }
    }
  end

  defp mapping(resource, table, template, poms) do
    %Resource{
      ash_resource: resource,
      logical_table: %LogicalTable{table_name: table},
      subject_map: %SubjectMap{strategy: :template, value: template, term_type: :iri},
      class_iris: ["https://example.org/Thing"],
      predicate_object_maps: poms,
      identities: [[:title]],
      metadata: %{source: :obda_query_unauthorized_test}
    }
  end

  defp spec(resource, table, template, attrs) do
    poms = for {attr, pred} <- attrs, do: pom(attr, pred)
    [{resource, mapping(resource, table, template, poms)}]
  end

  defp select(pred), do: "SELECT ?s ?o WHERE { ?s <#{pred}> ?o }"

  defp subjects(%OBDA.Result{bindings: rows}), do: rows |> Enum.map(&to_string(&1["s"])) |> Enum.sort()
  defp objects(%OBDA.Result{bindings: rows}), do: rows |> Enum.map(&to_string(&1["o"])) |> Enum.sort()

  setup do
    for resource <- [Gated, Fielded, Sensitive] do
      resource
      |> Ash.read!(authorize?: false, domain: Domain)
      |> Enum.each(&Ash.destroy!(&1, authorize?: false, domain: Domain))
    end

    for tenant <- ["A", "B"] do
      Tenanted
      |> Ash.read!(tenant: tenant, authorize?: false, domain: Domain)
      |> Enum.each(&Ash.destroy!(&1, tenant: tenant, authorize?: false, domain: Domain))
    end

    :ok
  end

  describe "actor without read policy" do
    setup do
      for title <- ["g1", "g2"] do
        Gated
        |> Ash.Changeset.for_create(:create, %{title: title}, domain: Domain)
        |> Ash.create!(authorize?: false, domain: Domain)
      end

      :ok
    end

    test "permitted actor reads both rows (positive control)" do
      specs = spec(Gated, "gated", "https://example.org/gated/{title}", title: @title_pred)

      assert {:ok, result} = OBDA.query(specs, select(@title_pred), domain: Domain, actor: %{role: :reader})
      assert subjects(result) == ["https://example.org/gated/g1", "https://example.org/gated/g2"]
      assert result.stats.resources_pruned_by_policy == 0
    end

    test "denied actor gets zero rows, zero materialized subjects and one pruned resource" do
      specs = spec(Gated, "gated", "https://example.org/gated/{title}", title: @title_pred)

      assert {:ok, result} = OBDA.query(specs, select(@title_pred), domain: Domain, actor: %{role: :stranger})
      assert result.bindings == []
      assert result.stats.rows_read == 0
      assert result.stats.triples_emitted == 0
      assert result.stats.resources_pruned_by_policy == 1
    end

    test "nil actor is denied the same way" do
      specs = spec(Gated, "gated", "https://example.org/gated/{title}", title: @title_pred)

      assert {:ok, result} = OBDA.query(specs, select(@title_pred), domain: Domain)
      assert result.bindings == []
      assert result.stats.rows_read == 0
      assert result.stats.resources_pruned_by_policy == 1
    end
  end

  describe "field policy (Ash.ForbiddenField)" do
    setup do
      for {title, secret} <- [{"f1", "s3cret-one"}, {"f2", "s3cret-two"}] do
        Fielded
        |> Ash.Changeset.for_create(:create, %{title: title, secret: secret}, domain: Domain)
        |> Ash.create!(authorize?: false, domain: Domain)
      end

      :ok
    end

    defp fielded_specs do
      spec(Fielded, "fielded", "https://example.org/fielded/{title}", title: @title_pred, secret: @secret_pred)
    end

    test "admin sees the field-policy-gated attribute (positive control)" do
      assert {:ok, result} = OBDA.query(fielded_specs(), select(@secret_pred), domain: Domain, actor: %{role: :admin})
      assert objects(result) == ["s3cret-one", "s3cret-two"]
    end

    test "non-admin: gated attribute is omitted from bindings and the graph, ungated attribute remains" do
      actor = %{role: :reader}

      assert {:ok, secret} = OBDA.query(fielded_specs(), select(@secret_pred), domain: Domain, actor: actor)
      assert secret.bindings == []

      assert {:ok, title} = OBDA.query(fielded_specs(), select(@title_pred), domain: Domain, actor: actor)
      assert subjects(title) == ["https://example.org/fielded/f1", "https://example.org/fielded/f2"]

      # Only the two title triples were materialized: no triple carries the denied field.
      assert title.stats.triples_emitted == 4
      refute inspect(title) =~ "s3cret"
      refute inspect(title) =~ "ForbiddenField"
      refute inspect(secret) =~ "ForbiddenField"
    end
  end

  describe "sensitive?: true attribute" do
    setup do
      Sensitive
      |> Ash.Changeset.for_create(:create, %{title: "t1", token: "tok-abc-123"}, domain: Domain)
      |> Ash.create!(authorize?: false, domain: Domain)

      :ok
    end

    test "mapped sensitive attribute is refused by default and no value is returned" do
      specs =
        spec(Sensitive, "sensitive", "https://example.org/sens/{title}", title: @title_pred, token: @token_pred)

      assert {:error, error} = OBDA.query(specs, select(@token_pred), domain: Domain, actor: %{role: :any})
      assert error.code == :REFUSED_SENSITIVE_ATTRIBUTE_MATERIALIZATION
      refute inspect(error) =~ "tok-abc-123"
    end

    test "unmapped sensitive attribute never appears in a query over the same resource" do
      specs = spec(Sensitive, "sensitive", "https://example.org/sens/{title}", title: @title_pred)

      assert {:ok, result} = OBDA.query(specs, select(@title_pred), domain: Domain, actor: %{role: :any})
      assert subjects(result) == ["https://example.org/sens/t1"]
      assert result.stats.triples_emitted == 2
      refute inspect(result) =~ "tok-abc-123"
    end

    test "allow_sensitive?: true is the only way the value is emitted (positive control)" do
      specs =
        spec(Sensitive, "sensitive", "https://example.org/sens/{title}", title: @title_pred, token: @token_pred)

      assert {:ok, result} =
               OBDA.query(specs, select(@token_pred), domain: Domain, actor: %{role: :any}, allow_sensitive?: true)

      assert objects(result) == ["tok-abc-123"]
    end
  end

  describe "tenant isolation" do
    setup do
      for {tenant, titles} <- [{"A", ["a1", "a2"]}, {"B", ["b1"]}], title <- titles do
        Tenanted
        |> Ash.Changeset.for_create(:create, %{title: title}, tenant: tenant, domain: Domain)
        |> Ash.create!(authorize?: false, tenant: tenant, domain: Domain)
      end

      :ok
    end

    defp tenant_specs, do: spec(Tenanted, "tenanted", "https://example.org/tenanted/{title}", title: @title_pred)

    test "tenant A sees only A rows and tenant B only B rows" do
      opts = [domain: Domain, actor: %{role: :any}]

      assert {:ok, a} = OBDA.query(tenant_specs(), select(@title_pred), [tenant: "A"] ++ opts)
      assert subjects(a) == ["https://example.org/tenanted/a1", "https://example.org/tenanted/a2"]
      assert a.stats.triples_emitted == 4

      assert {:ok, b} = OBDA.query(tenant_specs(), select(@title_pred), [tenant: "B"] ++ opts)
      assert subjects(b) == ["https://example.org/tenanted/b1"]
      assert b.stats.triples_emitted == 2
    end

    test "unknown tenant sees nothing" do
      assert {:ok, c} =
               OBDA.query(tenant_specs(), select(@title_pred), domain: Domain, actor: %{role: :any}, tenant: "C")

      assert c.bindings == []
    end

    test "missing tenant is refused with REFUSED_MISSING_TENANT, not a cross-tenant read" do
      assert {:error, error} = OBDA.query(tenant_specs(), select(@title_pred), domain: Domain, actor: %{role: :any})
      assert error.code == :REFUSED_MISSING_TENANT
    end
  end
end
