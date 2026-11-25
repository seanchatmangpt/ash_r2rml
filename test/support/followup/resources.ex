# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Followup.Domain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshR2RML.Followup.Renamed
    resource AshR2RML.Followup.GraphRow
    resource AshR2RML.Followup.LinkRow
    resource AshR2RML.Followup.ContextBare
    resource AshR2RML.Followup.ContextGlobal
  end
end

defmodule AshR2RML.Followup.Renamed do
  @moduledoc false
  use Ash.Resource, domain: AshR2RML.Followup.Domain, data_layer: Ash.DataLayer.Ets

  ets do
    private?(false)
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name, :ssn, :boss_code]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
    # stored under a different column name than the attribute name
    attribute :ssn, :string, public?: true, sensitive?: true, source: :db_ssn
    attribute :boss_code, :string, public?: true
  end
end

defmodule AshR2RML.Followup.GraphRow do
  @moduledoc false
  use Ash.Resource, domain: AshR2RML.Followup.Domain, data_layer: Ash.DataLayer.Ets

  ets do
    private?(false)
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name, :nick, :graph]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :nick, :string, allow_nil?: false, public?: true
    # nullable: a column graph map over it resolves nil for rows that leave it unset
    attribute :graph, :string, public?: true
  end
end

defmodule AshR2RML.Followup.LinkRow do
  @moduledoc false
  use Ash.Resource, domain: AshR2RML.Followup.Domain, data_layer: Ash.DataLayer.Ets

  ets do
    private?(false)
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:homepage]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :homepage, :string, allow_nil?: false, public?: true
  end
end

defmodule AshR2RML.Followup.ContextBare do
  @moduledoc false
  use Ash.Resource, domain: AshR2RML.Followup.Domain, data_layer: Ash.DataLayer.Ets

  ets do
    private?(false)
  end

  multitenancy do
    strategy :context
  end

  actions do
    defaults [:read]
  end

  attributes do
    uuid_primary_key :id
    attribute :code, :string, allow_nil?: false, public?: true
  end
end

defmodule AshR2RML.Followup.ContextGlobal do
  @moduledoc false
  use Ash.Resource, domain: AshR2RML.Followup.Domain, data_layer: Ash.DataLayer.Ets

  ets do
    private?(false)
  end

  multitenancy do
    strategy :context
  end

  actions do
    defaults [:read]
  end

  identities do
    identity :global_code, [:code], all_tenants?: true, pre_check_with: AshR2RML.Followup.Domain
  end

  attributes do
    uuid_primary_key :id
    attribute :code, :string, allow_nil?: false, public?: true
  end
end
