# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# R2RML-105: a real `AshPostgres.DataLayer`-backed fixture, distinct from the
# `Ash.DataLayer.Ets`-backed `AshR2RML.Fortune5.PaymentGateway` fixture. Its purpose is to
# exercise `AshR2RML.DataLayer.backend/1`'s `:postgres` branch and, through it,
# `AshR2RML.Security.sanitize_mapping/2`'s `:postgres`-gated exclusion path -- end to end
# through `AshR2RML.Compiler.compile_resources/1`, per R2RML-105 acceptance criterion #3.
#
# Nothing here ever starts or connects to a real database: `Ash.Resource.Info.data_layer/1`
# and `AshR2RML.Resource.Info.mapping_result/1` are pure DSL/module introspection, and Spark
# DSL compilation of an `AshPostgres.DataLayer`-backed resource does not require a live
# `Ecto.Repo` connection. `AshPostgresFixture.Repo` is a real `Ecto.Repo` module (compiled,
# genuinely implementing the `Ecto.Repo` behaviour) that is simply never started.

defmodule AshPostgresFixture.Repo do
  @moduledoc "A real, never-started `Ecto.Repo` backing `AshPostgresFixture.MerchantAccount`."
  use Ecto.Repo,
    otp_app: :ash_r2rml,
    adapter: Ecto.Adapters.Postgres
end

defmodule AshPostgresFixture.Domain do
  @moduledoc "A real `Ash.Domain` scoping the `AshPostgres.DataLayer`-backed fixture resource."
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshPostgresFixture.MerchantAccount
  end
end

defmodule AshPostgresFixture.MerchantAccount do
  @moduledoc """
  Mirrors `AshR2RML.Fortune5.PaymentGateway`'s field-policy shape (an R2RML-mapped attribute,
  `:secret_key`, restricted to `actor_attribute_equals(:role, :admin)`; `:display_name`
  unconditionally granted via `authorize_if always()`), but backed by `AshPostgres.DataLayer`
  instead of `Ash.DataLayer.Ets` -- the one detail R2RML-105 exists to cover, since
  `sanitize_mapping/2`'s `:postgres` branch has never been exercised end-to-end through a
  compiled resource before this fixture. Both attributes carry an explicit `field_policy`
  because Ash's own `AddMissingFieldPolicies` transformer requires full field coverage once any
  `field_policies` block is declared (`deps/ash/lib/ash/policy/authorizer/transformers/
  add_missing_field_policies.ex`) -- a `:*` catch-all or a second explicit block are the only
  compilable options, exactly the situation `AshR2RML.Security`'s moduledoc and the R2RML-106
  investigation (`documentation/jira_v26_8_25_ard.md`) already document: `field_policy_protected?/2`
  cannot and does not attempt to distinguish this unconditionally-granted `:display_name` policy
  from `:secret_key`'s genuinely conditional one.
  """
  use Ash.Resource,
    domain: AshPostgresFixture.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshR2RML]

  postgres do
    table "ash_postgres_fixture_merchant_accounts"
    repo(AshPostgresFixture.Repo)
  end

  r2rml do
    class_iri("https://schema.org/MerchantAccount")
    subject_template("https://finance.fortune5.com/merchant-accounts/{id}")
    table_name("ash_postgres_fixture_merchant_accounts")

    attribute_mappings([
      {:display_name, "https://schema.org/name"},
      {:secret_key, "https://w3id.org/fortune5/ontology#apiKeySecret"}
    ])
  end

  attributes do
    uuid_primary_key :id
    attribute :display_name, :string, allow_nil?: false, public?: true
    attribute :secret_key, :string, allow_nil?: false, public?: true
    timestamps()
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create do
      primary? true
      accept [:display_name, :secret_key]
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  field_policies do
    field_policy [:secret_key] do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    field_policy [:display_name] do
      authorize_if always()
    end
  end
end
