# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.AuditRegressions.Domain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshR2RML.AuditRegressions.GraphA
    resource AshR2RML.AuditRegressions.GraphB
    resource AshR2RML.AuditRegressions.Secretive
    resource AshR2RML.AuditRegressions.Fielded
    resource AshR2RML.AuditRegressions.TenantScoped
    resource AshR2RML.AuditRegressions.Locked
    resource AshR2RML.AuditRegressions.Bulk
  end
end

defmodule AshR2RML.AuditRegressions.GraphA do
  @moduledoc false
  use Ash.Resource, domain: AshR2RML.AuditRegressions.Domain, data_layer: Ash.DataLayer.Ets

  ets do
    private?(false)
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
  end
end

defmodule AshR2RML.AuditRegressions.GraphB do
  @moduledoc false
  use Ash.Resource, domain: AshR2RML.AuditRegressions.Domain, data_layer: Ash.DataLayer.Ets

  ets do
    private?(false)
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
  end
end

defmodule AshR2RML.AuditRegressions.Secretive do
  @moduledoc false
  use Ash.Resource, domain: AshR2RML.AuditRegressions.Domain, data_layer: Ash.DataLayer.Ets

  ets do
    private?(false)
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:label, :token]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :label, :string, allow_nil?: false, public?: true
    # stored under a different column name than the attribute name
    attribute :token, :string, public?: true, sensitive?: true, source: :db_secret
  end

  # Stand-in for a cloaked attribute: the plaintext is a derived field, not a real attribute.
  calculations do
    calculate :label_plain, :string, expr(label)
  end
end

defmodule AshR2RML.AuditRegressions.Fielded do
  @moduledoc false
  use Ash.Resource,
    domain: AshR2RML.AuditRegressions.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer]

  ets do
    private?(false)
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:title, :secret]
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  field_policies do
    field_policy :secret do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    field_policy :* do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, allow_nil?: false, public?: true
    attribute :secret, :string, public?: true
  end
end

defmodule AshR2RML.AuditRegressions.TenantScoped do
  @moduledoc false
  use Ash.Resource, domain: AshR2RML.AuditRegressions.Domain, data_layer: Ash.DataLayer.Ets

  ets do
    private?(false)
  end

  multitenancy do
    strategy :attribute
    attribute :org_id
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:code]
    end
  end

  identities do
    # all_tenants?: false (the default): unique per tenant only
    identity :by_code, [:code], pre_check_with: AshR2RML.AuditRegressions.Domain, all_tenants?: false
  end

  attributes do
    uuid_primary_key :id
    attribute :code, :string, allow_nil?: false, public?: true
    attribute :org_id, :string, allow_nil?: false, public?: true
  end
end

defmodule AshR2RML.AuditRegressions.Locked do
  @moduledoc false
  use Ash.Resource,
    domain: AshR2RML.AuditRegressions.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer]

  ets do
    private?(false)
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:title]
    end
  end

  policies do
    bypass action_type(:create) do
      authorize_if always()
    end

    bypass action_type(:destroy) do
      authorize_if always()
    end

    policy action_type(:read) do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, allow_nil?: false, public?: true
  end
end

defmodule AshR2RML.AuditRegressions.Bulk do
  @moduledoc false
  use Ash.Resource, domain: AshR2RML.AuditRegressions.Domain, data_layer: Ash.DataLayer.Ets

  ets do
    private?(false)
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
  end
end
