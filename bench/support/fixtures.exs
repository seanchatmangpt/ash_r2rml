# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Bench.Fixtures.Domain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshR2RML.Bench.Fixtures.Org
    resource AshR2RML.Bench.Fixtures.Person
    resource AshR2RML.Bench.Fixtures.SlowResource
    resource AshR2RML.Bench.Fixtures.HeapBomb
    resource AshR2RML.Bench.Fixtures.Wide30
  end
end

defmodule AshR2RML.Bench.Fixtures.Org do
  @moduledoc false
  use Ash.Resource,
    domain: AshR2RML.Bench.Fixtures.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML.Resource]

  actions do
    defaults [:read, :destroy, create: [:code, :name]]
  end

  attributes do
    uuid_primary_key :id
    attribute :code, :string, allow_nil?: false, public?: true
    attribute :name, :string, allow_nil?: false, public?: true
  end

  r2rml do
    table_name("bench_orgs")
    class("https://www.w3.org/ns/org#Organization")

    subject template: "https://bench.example.test/org/{id}"

    property(:code, "https://bench.example.test/ontology/code")
    property(:name, "http://xmlns.com/foaf/0.1/name")
  end
end

defmodule AshR2RML.Bench.Fixtures.Person do
  @moduledoc """
  Person belongs_to Org, composite subject template (`org_code` + `ext_id`),
  role policy (admin sees all, member sees own org, outsider sees none) and a
  field policy that hides the sensitive `ssn` from non-admins.

  Actors are maps `%{role: :admin | :member | :outsider, org_id: uuid | nil}`.
  """
  use Ash.Resource,
    domain: AshR2RML.Bench.Fixtures.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshR2RML.Resource]

  actions do
    defaults [:read, :destroy, create: [:org_code, :ext_id, :name, :ssn, :organization_id]]
  end

  policies do
    policy action_type([:create, :update, :destroy]) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if expr(^actor(:role) == :admin)
      authorize_if expr(^actor(:role) == :member and organization_id == ^actor(:org_id))
    end
  end

  field_policies do
    field_policy :ssn do
      authorize_if expr(^actor(:role) == :admin)
    end

    field_policy :* do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :org_code, :string, allow_nil?: false, public?: true
    attribute :ext_id, :string, allow_nil?: false, public?: true
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :ssn, :string, public?: true, sensitive?: true
  end

  relationships do
    belongs_to :organization, AshR2RML.Bench.Fixtures.Org,
      allow_nil?: false,
      public?: true
  end

  identities do
    identity :by_composite_key, [:org_code, :ext_id]
  end

  r2rml do
    table_name("bench_people")
    class("https://schema.org/Person")

    subject template: "https://bench.example.test/person/{org_code}/{ext_id}"

    property(:org_code, "https://bench.example.test/ontology/orgCode")
    property(:ext_id, "https://bench.example.test/ontology/extId")
    property(:name, "http://xmlns.com/foaf/0.1/name")
    reference(:organization, "https://www.w3.org/ns/org#memberOf")
  end
end

defmodule AshR2RML.Bench.Fixtures.SlowRead do
  @moduledoc """
  Manual read that blocks for `Application.get_env(:ash_r2rml, :bench_slow_ms, 50)`
  milliseconds. The sleep IS the stressor (a real slow data source), not a
  synchronization step.
  """
  use Ash.Resource.ManualRead

  @impl true
  def read(query, _data_layer_query, _opts, _context) do
    # SLEEP-CLASS: SCHEDULING (bench stressor: a real slow data source, never synchronization)
    :timer.sleep(Application.get_env(:ash_r2rml, :bench_slow_ms, 50))
    rows = Application.get_env(:ash_r2rml, :bench_slow_rows, 3)

    {:ok,
     for i <- 1..rows//1 do
       struct(query.resource, id: Ash.UUID.generate(), name: "slow-#{i}")
     end}
  end
end

defmodule AshR2RML.Bench.Fixtures.SlowResource do
  @moduledoc false
  use Ash.Resource,
    domain: AshR2RML.Bench.Fixtures.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML.Resource]

  actions do
    read :read do
      primary? true
      manual AshR2RML.Bench.Fixtures.SlowRead
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
  end

  r2rml do
    table_name("bench_slow")
    class("https://bench.example.test/ontology/Slow")

    subject template: "https://bench.example.test/slow/{id}"

    property(:name, "http://xmlns.com/foaf/0.1/name")
  end
end

defmodule AshR2RML.Bench.Fixtures.HeapBomb do
  @moduledoc "Wide binary fields; seed with a large `:payload_bytes` to pressure the heap."
  use Ash.Resource,
    domain: AshR2RML.Bench.Fixtures.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML.Resource]

  actions do
    defaults [:read, :destroy, create: [:blob_a, :blob_b, :blob_c, :blob_d]]
  end

  attributes do
    uuid_primary_key :id
    attribute :blob_a, :string, public?: true
    attribute :blob_b, :string, public?: true
    attribute :blob_c, :string, public?: true
    attribute :blob_d, :string, public?: true
  end

  r2rml do
    table_name("bench_heap_bomb")
    class("https://bench.example.test/ontology/HeapBomb")

    subject template: "https://bench.example.test/bomb/{id}"

    property(:blob_a, "https://bench.example.test/ontology/blobA")
    property(:blob_b, "https://bench.example.test/ontology/blobB")
    property(:blob_c, "https://bench.example.test/ontology/blobC")
    property(:blob_d, "https://bench.example.test/ontology/blobD")
  end
end

defmodule AshR2RML.Bench.Fixtures.Wide30 do
  @moduledoc "30 mapped string attributes: one row fans out to 30 literal triples plus type."
  use Ash.Resource,
    domain: AshR2RML.Bench.Fixtures.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML.Resource]

  actions do
    defaults [
      :read,
      :destroy,
      create: [
        :f01, :f02, :f03, :f04, :f05, :f06, :f07, :f08, :f09, :f10,
        :f11, :f12, :f13, :f14, :f15, :f16, :f17, :f18, :f19, :f20,
        :f21, :f22, :f23, :f24, :f25, :f26, :f27, :f28, :f29, :f30
      ]
    ]
  end

  attributes do
    uuid_primary_key :id
    attribute :f01, :string, public?: true
    attribute :f02, :string, public?: true
    attribute :f03, :string, public?: true
    attribute :f04, :string, public?: true
    attribute :f05, :string, public?: true
    attribute :f06, :string, public?: true
    attribute :f07, :string, public?: true
    attribute :f08, :string, public?: true
    attribute :f09, :string, public?: true
    attribute :f10, :string, public?: true
    attribute :f11, :string, public?: true
    attribute :f12, :string, public?: true
    attribute :f13, :string, public?: true
    attribute :f14, :string, public?: true
    attribute :f15, :string, public?: true
    attribute :f16, :string, public?: true
    attribute :f17, :string, public?: true
    attribute :f18, :string, public?: true
    attribute :f19, :string, public?: true
    attribute :f20, :string, public?: true
    attribute :f21, :string, public?: true
    attribute :f22, :string, public?: true
    attribute :f23, :string, public?: true
    attribute :f24, :string, public?: true
    attribute :f25, :string, public?: true
    attribute :f26, :string, public?: true
    attribute :f27, :string, public?: true
    attribute :f28, :string, public?: true
    attribute :f29, :string, public?: true
    attribute :f30, :string, public?: true
  end

  r2rml do
    table_name("bench_wide30")
    class("https://bench.example.test/ontology/Wide30")

    subject template: "https://bench.example.test/wide/{id}"

    property(:f01, "https://bench.example.test/ontology/f01")
    property(:f02, "https://bench.example.test/ontology/f02")
    property(:f03, "https://bench.example.test/ontology/f03")
    property(:f04, "https://bench.example.test/ontology/f04")
    property(:f05, "https://bench.example.test/ontology/f05")
    property(:f06, "https://bench.example.test/ontology/f06")
    property(:f07, "https://bench.example.test/ontology/f07")
    property(:f08, "https://bench.example.test/ontology/f08")
    property(:f09, "https://bench.example.test/ontology/f09")
    property(:f10, "https://bench.example.test/ontology/f10")
    property(:f11, "https://bench.example.test/ontology/f11")
    property(:f12, "https://bench.example.test/ontology/f12")
    property(:f13, "https://bench.example.test/ontology/f13")
    property(:f14, "https://bench.example.test/ontology/f14")
    property(:f15, "https://bench.example.test/ontology/f15")
    property(:f16, "https://bench.example.test/ontology/f16")
    property(:f17, "https://bench.example.test/ontology/f17")
    property(:f18, "https://bench.example.test/ontology/f18")
    property(:f19, "https://bench.example.test/ontology/f19")
    property(:f20, "https://bench.example.test/ontology/f20")
    property(:f21, "https://bench.example.test/ontology/f21")
    property(:f22, "https://bench.example.test/ontology/f22")
    property(:f23, "https://bench.example.test/ontology/f23")
    property(:f24, "https://bench.example.test/ontology/f24")
    property(:f25, "https://bench.example.test/ontology/f25")
    property(:f26, "https://bench.example.test/ontology/f26")
    property(:f27, "https://bench.example.test/ontology/f27")
    property(:f28, "https://bench.example.test/ontology/f28")
    property(:f29, "https://bench.example.test/ontology/f29")
    property(:f30, "https://bench.example.test/ontology/f30")
  end
end

defmodule AshR2RML.Bench.Fixtures do
  @moduledoc """
  Real ETS-backed Ash fixtures for the bench scripts. No doubles.

  Actors for `Person`: `admin/0`, `member/1`, `outsider/0`.
  """

  alias AshR2RML.Bench.Fixtures.{HeapBomb, Org, Person, Wide30}

  @doc "All fixture resources."
  def resources do
    [Org, Person, AshR2RML.Bench.Fixtures.SlowResource, HeapBomb, Wide30]
  end

  def domain, do: AshR2RML.Bench.Fixtures.Domain

  def admin, do: %{role: :admin, org_id: nil}
  def member(org_id), do: %{role: :member, org_id: org_id}
  def outsider, do: %{role: :outsider, org_id: nil}

  @doc """
  Seeds `n_orgs` orgs and `n` people spread round-robin across them via
  `Ash.bulk_create/4`. Returns `%{orgs: [Org.t()], people: [Person.t()]}`.
  """
  @spec seed(non_neg_integer(), keyword()) :: %{orgs: list(), people: list()}
  def seed(n, opts \\ []) when is_integer(n) and n >= 0 do
    n_orgs = Keyword.get(opts, :orgs, 3)
    tag = Keyword.get(opts, :tag, System.unique_integer([:positive]))

    orgs =
      bulk!(
        for(i <- 1..n_orgs//1, do: %{code: "o#{tag}-#{i}", name: "Org #{i}"}),
        Org,
        :create
      )

    org_list = List.to_tuple(orgs)

    people =
      bulk!(
        for i <- 1..n//1 do
          org = elem(org_list, rem(i, n_orgs))

          %{
            org_code: org.code,
            ext_id: "p#{tag}-#{i}",
            name: "Person #{i}",
            ssn: "000-00-#{String.pad_leading(Integer.to_string(i), 4, "0")}",
            organization_id: org.id
          }
        end,
        Person,
        :create
      )

    %{orgs: orgs, people: people}
  end

  @doc "Seeds `n` HeapBomb rows with four `payload_bytes`-sized binary fields each."
  def seed_heap_bomb(n, payload_bytes) do
    blob = String.duplicate("x", payload_bytes)

    bulk!(
      for(_ <- 1..n//1, do: %{blob_a: blob, blob_b: blob, blob_c: blob, blob_d: blob}),
      HeapBomb,
      :create
    )
  end

  @doc "Seeds `n` Wide30 rows (30 populated attributes each)."
  def seed_wide30(n) do
    bulk!(
      for i <- 1..n//1 do
        for f <- 1..30, into: %{} do
          {:"f#{String.pad_leading(Integer.to_string(f), 2, "0")}", "v#{i}-#{f}"}
        end
      end,
      Wide30,
      :create
    )
  end

  defp bulk!([], _resource, _action), do: []

  defp bulk!(inputs, resource, action) do
    %Ash.BulkResult{records: records, status: :success} =
      Ash.bulk_create!(inputs, resource, action,
        authorize?: false,
        return_records?: true,
        return_errors?: true,
        stop_on_error?: true
      )

    records
  end
end
