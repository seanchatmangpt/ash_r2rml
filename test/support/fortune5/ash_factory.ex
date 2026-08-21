# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Fortune5.Types.CurrencyAmount do
  @moduledoc """
  Custom Ash scalar type representing enterprise currency amounts with currency ISO codes
  and XSD/Schema.org datatype serialization for R2RML.
  """
  use Ash.Type

  use AshR2RML.Type,
    xsd_datatype: "https://schema.org/MonetaryAmount"

  @impl Ash.Type
  def storage_type(_), do: :map

  @impl Ash.Type
  def cast_input(%{amount: amount, currency: currency}, _) when is_binary(currency) do
    case to_decimal(amount) do
      {:ok, dec} -> {:ok, %{amount: dec, currency: String.upcase(currency)}}
      :error -> {:error, "Invalid monetary amount"}
    end
  end

  def cast_input(%{"amount" => amount, "currency" => currency}, _) when is_binary(currency) do
    case to_decimal(amount) do
      {:ok, dec} -> {:ok, %{amount: dec, currency: String.upcase(currency)}}
      :error -> {:error, "Invalid monetary amount"}
    end
  end

  def cast_input({amount, currency}, _) when is_binary(currency) do
    case to_decimal(amount) do
      {:ok, dec} -> {:ok, %{amount: dec, currency: String.upcase(currency)}}
      :error -> {:error, "Invalid monetary amount"}
    end
  end

  def cast_input(value, _) when is_binary(value) do
    case String.split(String.trim(value), ~r/\s+/) do
      [amount_str, currency] ->
        case Decimal.parse(amount_str) do
          {dec, ""} -> {:ok, %{amount: dec, currency: String.upcase(currency)}}
          _ -> {:error, "Invalid monetary amount format"}
        end

      [amount_str] ->
        case Decimal.parse(amount_str) do
          {dec, ""} -> {:ok, %{amount: dec, currency: "USD"}}
          _ -> {:error, "Invalid monetary amount format"}
        end

      _ ->
        {:error, "Invalid currency amount format"}
    end
  end

  def cast_input(value, _) do
    case to_decimal(value) do
      {:ok, dec} -> {:ok, %{amount: dec, currency: "USD"}}
      :error -> {:error, "Invalid currency amount"}
    end
  end

  @impl Ash.Type
  def cast_stored(nil, _), do: {:ok, nil}

  def cast_stored(%{amount: amount, currency: currency}, _) do
    {:ok, %{amount: Decimal.new(to_string(amount)), currency: to_string(currency)}}
  end

  def cast_stored(%{"amount" => amount, "currency" => currency}, _) do
    {:ok, %{amount: Decimal.new(to_string(amount)), currency: to_string(currency)}}
  end

  def cast_stored(value, _) when is_binary(value) do
    cast_input(value, [])
  end

  def cast_stored(_, _), do: {:error, "Invalid stored monetary amount"}

  @impl Ash.Type
  def dump_to_native(nil, _), do: {:ok, nil}

  def dump_to_native(%{amount: amount, currency: currency}, _) do
    {:ok, %{amount: to_string(amount), currency: to_string(currency)}}
  end

  def dump_to_native(other, opts), do: cast_input(other, opts)

  @impl Ash.Type
  def dump_to_embedded(nil, _), do: {:ok, nil}

  def dump_to_embedded(%{amount: amount, currency: currency}, _) do
    {:ok, %{amount: to_string(amount), currency: to_string(currency)}}
  end

  def dump_to_embedded(other, opts), do: dump_to_native(other, opts)

  @impl AshR2RML.Type
  def to_rdf_lexical(%{amount: amount, currency: currency}) do
    "#{Decimal.to_string(amount)} #{currency}"
  end

  def to_rdf_lexical(value), do: to_string(value)

  @impl AshR2RML.Type
  def from_rdf_lexical(str) when is_binary(str) do
    cast_input(str, [])
  end

  defp to_decimal(%Decimal{} = dec), do: {:ok, dec}
  defp to_decimal(val) when is_integer(val), do: {:ok, Decimal.new(val)}
  defp to_decimal(val) when is_float(val), do: {:ok, Decimal.from_float(val)}

  defp to_decimal(val) when is_binary(val) do
    case Decimal.parse(val) do
      {dec, ""} -> {:ok, dec}
      _ -> :error
    end
  end

  defp to_decimal(_), do: :error
end

defmodule AshR2RML.Fortune5.Types.IPAddressRange do
  @moduledoc """
  Custom Ash scalar type representing CIDR network address ranges for cloud clusters.
  """
  use Ash.Type

  use AshR2RML.Type,
    xsd_datatype: "http://www.w3.org/2001/XMLSchema#string"

  @impl Ash.Type
  def storage_type(_), do: :string

  @impl Ash.Type
  def cast_input(value, _) when is_binary(value) do
    trimmed = String.trim(value)

    if valid_cidr?(trimmed) do
      {:ok, trimmed}
    else
      {:error, "Invalid IP CIDR range: #{trimmed}"}
    end
  end

  def cast_input(_, _), do: {:error, "IP range must be a string in CIDR notation (e.g. 10.0.0.0/16)"}

  @impl Ash.Type
  def cast_stored(nil, _), do: {:ok, nil}
  def cast_stored(value, _), do: {:ok, to_string(value)}

  @impl Ash.Type
  def dump_to_native(nil, _), do: {:ok, nil}
  def dump_to_native(value, _), do: {:ok, to_string(value)}

  @impl Ash.Type
  def dump_to_embedded(nil, _), do: {:ok, nil}
  def dump_to_embedded(value, _), do: {:ok, to_string(value)}

  @impl AshR2RML.Type
  def to_rdf_lexical(value), do: to_string(value)

  @impl AshR2RML.Type
  def from_rdf_lexical(str), do: {:ok, str}

  defp valid_cidr?(cidr) do
    case String.split(cidr, "/") do
      [ip, prefix] ->
        with {prefix_int, ""} <- Integer.parse(prefix),
             true <- prefix_int >= 0 and prefix_int <= 128,
             {:ok, _parsed_ip} <- parse_ip(ip) do
          true
        else
          _ -> false
        end

      _ ->
        case parse_ip(cidr) do
          {:ok, _} -> true
          _ -> false
        end
    end
  end

  defp parse_ip(ip_str) do
    case :inet.parse_address(String.to_charlist(ip_str)) do
      {:ok, addr} -> {:ok, addr}
      {:error, _} -> :error
    end
  end
end

defmodule AshR2RML.Fortune5.Types.CriticalityEnum do
  @moduledoc """
  Custom Ash scalar type for enterprise system criticality tiers.
  """
  use Ash.Type

  use AshR2RML.Type,
    xsd_datatype: "http://www.w3.org/2001/XMLSchema#string"

  @values [:low, :medium, :high, :mission_critical]

  @impl Ash.Type
  def storage_type(_), do: :string

  @impl Ash.Type
  def cast_input(value, _) when value in @values, do: {:ok, value}

  def cast_input(value, _) when is_binary(value) do
    atom_val = String.to_existing_atom(value)
    if atom_val in @values, do: {:ok, atom_val}, else: {:error, "Invalid criticality: #{value}"}
  rescue
    _ -> {:error, "Invalid criticality: #{value}"}
  end

  def cast_input(_, _), do: {:error, "Criticality must be one of: #{inspect(@values)}"}

  @impl Ash.Type
  def cast_stored(nil, _), do: {:ok, nil}

  def cast_stored(value, _) when is_binary(value) do
    {:ok, String.to_atom(value)}
  end

  def cast_stored(value, _) when value in @values, do: {:ok, value}
  def cast_stored(_, _), do: {:error, "Invalid stored criticality"}

  @impl Ash.Type
  def dump_to_native(nil, _), do: {:ok, nil}
  def dump_to_native(value, _) when is_atom(value), do: {:ok, Atom.to_string(value)}
  def dump_to_native(value, _), do: {:ok, to_string(value)}

  @impl Ash.Type
  def dump_to_embedded(nil, _), do: {:ok, nil}
  def dump_to_embedded(value, opts), do: dump_to_native(value, opts)

  @impl AshR2RML.Type
  def to_rdf_lexical(value), do: to_string(value)

  @impl AshR2RML.Type
  def from_rdf_lexical(str) do
    cast_input(str, [])
  end

  def values, do: @values
end

defmodule AshR2RML.Fortune5.Calculations.UptimeSla do
  @moduledoc """
  Calculation computing target SLA uptime percentage based on error budget.
  """
  use Ash.Resource.Calculation

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn record ->
      budget = Map.get(record, :error_budget) || Decimal.new("99.99")
      Decimal.to_string(budget) <> "%"
    end)
  end
end

defmodule AshR2RML.Fortune5.Domain do
  @moduledoc """
  Ash Domain aggregating all Fortune 5 enterprise cloud, infrastructure, and financial resources.
  """
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshR2RML.Fortune5.CloudRegion
    resource AshR2RML.Fortune5.Cluster
    resource AshR2RML.Fortune5.ServiceInstance
    resource AshR2RML.Fortune5.PaymentGateway
    resource AshR2RML.Fortune5.LedgerAccount
    resource AshR2RML.Fortune5.DeploymentPlan
    resource AshR2RML.Fortune5.DeploymentPlanService
    resource AshR2RML.Fortune5.IncidentTicket
    resource AshR2RML.Fortune5.CredentialGrant
  end
end

defmodule AshR2RML.Fortune5.CloudRegion do
  @moduledoc """
  Enterprise Cloud Datacenter Region resource.
  """
  use Ash.Resource,
    domain: AshR2RML.Fortune5.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshR2RML]

  r2rml do
    class_iri("https://schema.org/Place")
    subject_template("https://cloud.fortune5.com/regions/{id}")
    table_name("fortune5_cloud_regions")

    attribute_mappings([
      {:name, "https://schema.org/name"},
      {:code, "https://schema.org/identifier"},
      {:datacenter_location, "https://schema.org/address"},
      {:status, "https://schema.org/status"}
    ])

    relationship_mappings([
      {:clusters, "https://w3id.org/fortune5/ontology#hasCluster"},
      {:payment_gateways, "https://w3id.org/fortune5/ontology#hostsPaymentGateway"}
    ])
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :code, :string, allow_nil?: false, public?: true
    attribute :datacenter_location, :string, allow_nil?: false, public?: true

    attribute :status, :atom,
      constraints: [one_of: [:active, :degraded, :isolated, :maintenance]],
      default: :active,
      public?: true

    timestamps()
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create do
      primary? true
      accept [:name, :code, :datacenter_location, :status]
    end

    update :isolate do
      accept [:status]
      change set_attribute(:status, :isolated)
    end

    update :reconnect do
      accept [:status]
      change set_attribute(:status, :active)
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  relationships do
    has_many :clusters, AshR2RML.Fortune5.Cluster do
      source_attribute :id
      destination_attribute :cloud_region_id
    end

    has_many :payment_gateways, AshR2RML.Fortune5.PaymentGateway do
      source_attribute :id
      destination_attribute :cloud_region_id
    end
  end
end

defmodule AshR2RML.Fortune5.Cluster do
  @moduledoc """
  Kubernetes / Baremetal Compute Cluster resource.
  """
  use Ash.Resource,
    domain: AshR2RML.Fortune5.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshR2RML]

  r2rml do
    class_iri("https://schema.org/ComputeCluster")
    subject_template("https://cloud.fortune5.com/clusters/{id}")
    table_name("fortune5_clusters")

    attribute_mappings([
      {:name, "https://schema.org/name"},
      {:ip_range, "https://w3id.org/fortune5/ontology#ipRange"},
      {:criticality, "https://w3id.org/fortune5/ontology#criticalityLevel"},
      {:node_count, "https://schema.org/numberOfItems"}
    ])

    relationship_mappings([
      {:cloud_region, "https://w3id.org/fortune5/ontology#inRegion"},
      {:service_instances, "https://w3id.org/fortune5/ontology#hostsService"},
      {:deployment_plans, "https://w3id.org/fortune5/ontology#targetedByPlan"}
    ])
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :ip_range, AshR2RML.Fortune5.Types.IPAddressRange, allow_nil?: false, public?: true
    attribute :criticality, AshR2RML.Fortune5.Types.CriticalityEnum, default: :high, public?: true
    attribute :node_count, :integer, default: 3, public?: true
    attribute :cloud_region_id, :uuid, allow_nil?: true, public?: true
    timestamps()
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create do
      primary? true
      accept [:name, :ip_range, :criticality, :node_count, :cloud_region_id]
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  relationships do
    belongs_to :cloud_region, AshR2RML.Fortune5.CloudRegion do
      source_attribute :cloud_region_id
      destination_attribute :id
      attribute_writable? true
    end

    has_many :service_instances, AshR2RML.Fortune5.ServiceInstance do
      source_attribute :id
      destination_attribute :cluster_id
    end

    has_many :deployment_plans, AshR2RML.Fortune5.DeploymentPlan do
      source_attribute :id
      destination_attribute :cluster_id
    end
  end
end

defmodule AshR2RML.Fortune5.ServiceInstance do
  @moduledoc """
  Microservice container/instance with SLA calculations and incident tracking.
  """
  use Ash.Resource,
    domain: AshR2RML.Fortune5.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshR2RML]

  r2rml do
    class_iri("https://schema.org/SoftwareApplication")
    subject_template("https://cloud.fortune5.com/services/{id}")
    table_name("fortune5_service_instances")

    attribute_mappings([
      {:name, "https://schema.org/name"},
      {:version, "https://schema.org/softwareVersion"},
      {:endpoint_url, "https://schema.org/url"},
      {:status, "https://schema.org/status"},
      {:error_budget, "https://w3id.org/fortune5/ontology#errorBudget"}
    ])

    relationship_mappings([
      {:cluster, "https://w3id.org/fortune5/ontology#runsOnCluster"},
      {:incident_tickets, "https://w3id.org/fortune5/ontology#hasIncident"},
      {:deployment_plan_services, "https://w3id.org/fortune5/ontology#hasPlanMapping"}
    ])
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :version, :string, allow_nil?: false, default: "1.0.0", public?: true
    attribute :endpoint_url, :string, allow_nil?: false, public?: true

    attribute :status, :atom,
      constraints: [one_of: [:running, :draining, :stopped, :failed, :provisioning]],
      default: :running,
      public?: true

    attribute :error_budget, :decimal, default: Decimal.new("99.99"), public?: true
    attribute :cluster_id, :uuid, allow_nil?: true, public?: true
    timestamps()
  end

  calculations do
    calculate :sla_label, :string, AshR2RML.Fortune5.Calculations.UptimeSla
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create do
      primary? true
      accept [:name, :version, :endpoint_url, :status, :error_budget, :cluster_id]
    end

    update :drain do
      accept [:status]
      change set_attribute(:status, :draining)
    end

    update :activate do
      accept [:status]
      change set_attribute(:status, :running)
    end

    update :stop do
      accept [:status]
      change set_attribute(:status, :stopped)
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  field_policies do
    field_policy [:name, :version, :endpoint_url, :status, :error_budget, :cluster_id] do
      authorize_if always()
    end
  end

  relationships do
    belongs_to :cluster, AshR2RML.Fortune5.Cluster do
      source_attribute :cluster_id
      destination_attribute :id
      attribute_writable? true
    end

    has_many :incident_tickets, AshR2RML.Fortune5.IncidentTicket do
      source_attribute :id
      destination_attribute :service_instance_id
    end

    has_many :deployment_plan_services, AshR2RML.Fortune5.DeploymentPlanService do
      source_attribute :id
      destination_attribute :service_instance_id
    end

    many_to_many :deployment_plans, AshR2RML.Fortune5.DeploymentPlan do
      through AshR2RML.Fortune5.DeploymentPlanService
      source_attribute_on_join_resource :service_instance_id
      destination_attribute_on_join_resource :deployment_plan_id
    end
  end
end

defmodule AshR2RML.Fortune5.PaymentGateway do
  @moduledoc """
  Financial Payment Gateway integration with ODRL policy-protected secret credentials.
  """
  use Ash.Resource,
    domain: AshR2RML.Fortune5.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshR2RML]

  r2rml do
    class_iri("https://schema.org/FinancialService")
    subject_template("https://finance.fortune5.com/gateways/{id}")
    table_name("fortune5_payment_gateways")

    attribute_mappings([
      {:name, "https://schema.org/name"},
      {:provider, "https://schema.org/provider"},
      {:api_endpoint, "https://schema.org/serviceUrl"},
      {:secret_key, "https://w3id.org/fortune5/ontology#apiKeySecret"},
      {:criticality, "https://w3id.org/fortune5/ontology#criticalityLevel"},
      {:status, "https://schema.org/status"}
    ])

    relationship_mappings([
      {:cloud_region, "https://w3id.org/fortune5/ontology#locatedInRegion"},
      {:ledger_accounts, "https://w3id.org/fortune5/ontology#managesAccount"}
    ])
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :provider, :string, allow_nil?: false, public?: true
    attribute :api_endpoint, :string, allow_nil?: false, public?: true
    attribute :secret_key, :string, allow_nil?: false, public?: true
    attribute :criticality, AshR2RML.Fortune5.Types.CriticalityEnum, default: :mission_critical, public?: true
    attribute :status, :atom, constraints: [one_of: [:active, :standby, :suspended]], default: :active, public?: true
    attribute :cloud_region_id, :uuid, allow_nil?: true, public?: true
    timestamps()
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create do
      primary? true
      accept [:name, :provider, :api_endpoint, :secret_key, :criticality, :status, :cloud_region_id]
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  field_policies do
    # ODRL Prohibition / Constraint: secret key only accessible to :admin
    field_policy [:secret_key] do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    field_policy [:name, :provider, :api_endpoint, :criticality, :status, :cloud_region_id] do
      authorize_if always()
    end
  end

  relationships do
    belongs_to :cloud_region, AshR2RML.Fortune5.CloudRegion do
      source_attribute :cloud_region_id
      destination_attribute :id
      attribute_writable? true
    end

    has_many :ledger_accounts, AshR2RML.Fortune5.LedgerAccount do
      source_attribute :id
      destination_attribute :payment_gateway_id
    end
  end
end

defmodule AshR2RML.Fortune5.LedgerAccount do
  @moduledoc """
  Enterprise Bank and General Ledger Account resource with custom CurrencyAmount type.
  """
  use Ash.Resource,
    domain: AshR2RML.Fortune5.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshR2RML]

  r2rml do
    class_iri("https://schema.org/BankAccount")
    subject_template("https://finance.fortune5.com/accounts/{id}")
    table_name("fortune5_ledger_accounts")

    attribute_mappings([
      {:account_number, "https://schema.org/identifier"},
      {:balance, "https://schema.org/amount"},
      {:currency, "https://schema.org/currency"},
      {:risk_score, "https://w3id.org/fortune5/ontology#riskAssessmentScore"},
      {:status, "https://schema.org/status"}
    ])

    relationship_mappings([
      {:payment_gateway, "https://w3id.org/fortune5/ontology#clearedByGateway"},
      {:credential_grants, "https://w3id.org/fortune5/ontology#hasCredential"}
    ])
  end

  attributes do
    uuid_primary_key :id
    attribute :account_number, :string, allow_nil?: false, public?: true
    attribute :balance, AshR2RML.Fortune5.Types.CurrencyAmount, allow_nil?: false, public?: true
    attribute :currency, :string, default: "USD", public?: true
    attribute :risk_score, :decimal, default: Decimal.new("0.05"), public?: true
    attribute :status, :atom, constraints: [one_of: [:active, :frozen, :closed]], default: :active, public?: true
    attribute :payment_gateway_id, :uuid, allow_nil?: true, public?: true
    timestamps()
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create do
      primary? true
      accept [:account_number, :balance, :currency, :risk_score, :status, :payment_gateway_id]
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  field_policies do
    # ODRL Policy: risk_score restricted to compliance auditors and admins
    field_policy [:risk_score] do
      authorize_if actor_attribute_equals(:role, :compliance_auditor)
    end

    field_policy [:risk_score] do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    field_policy [:account_number, :balance, :currency, :status, :payment_gateway_id] do
      authorize_if always()
    end
  end

  relationships do
    belongs_to :payment_gateway, AshR2RML.Fortune5.PaymentGateway do
      source_attribute :payment_gateway_id
      destination_attribute :id
      attribute_writable? true
    end

    has_many :credential_grants, AshR2RML.Fortune5.CredentialGrant do
      source_attribute :id
      destination_attribute :ledger_account_id
    end
  end
end

defmodule AshR2RML.Fortune5.DeploymentPlan do
  @moduledoc """
  Deployment Execution Plan resource for continuous multi-cluster delivery.
  """
  use Ash.Resource,
    domain: AshR2RML.Fortune5.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshR2RML]

  r2rml do
    class_iri("https://schema.org/Plan")
    subject_template("https://deploy.fortune5.com/plans/{id}")
    table_name("fortune5_deployment_plans")

    attribute_mappings([
      {:plan_code, "https://schema.org/identifier"},
      {:target_version, "https://schema.org/softwareVersion"},
      {:strategy, "https://w3id.org/fortune5/ontology#deploymentStrategy"},
      {:status, "https://schema.org/status"},
      {:budget_limit, "https://schema.org/budget"}
    ])

    relationship_mappings([
      {:cluster, "https://w3id.org/fortune5/ontology#deploysToCluster"},
      {:deployment_plan_services, "https://w3id.org/fortune5/ontology#hasServiceMapping"}
    ])
  end

  attributes do
    uuid_primary_key :id
    attribute :plan_code, :string, allow_nil?: false, public?: true
    attribute :target_version, :string, allow_nil?: false, public?: true

    attribute :strategy, :atom,
      constraints: [one_of: [:blue_green, :canary, :rolling, :recreate]],
      default: :blue_green,
      public?: true

    attribute :status, :atom,
      constraints: [one_of: [:pending, :in_progress, :deployed, :rolled_back, :failed]],
      default: :pending,
      public?: true

    attribute :budget_limit, AshR2RML.Fortune5.Types.CurrencyAmount, allow_nil?: true, public?: true
    attribute :cluster_id, :uuid, allow_nil?: true, public?: true
    timestamps()
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create do
      primary? true
      accept [:plan_code, :target_version, :strategy, :status, :budget_limit, :cluster_id]
    end

    update :mark_deployed do
      accept [:status]
      change set_attribute(:status, :deployed)
    end

    update :mark_rolled_back do
      accept [:status]
      change set_attribute(:status, :rolled_back)
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  relationships do
    belongs_to :cluster, AshR2RML.Fortune5.Cluster do
      source_attribute :cluster_id
      destination_attribute :id
      attribute_writable? true
    end

    has_many :deployment_plan_services, AshR2RML.Fortune5.DeploymentPlanService do
      source_attribute :id
      destination_attribute :deployment_plan_id
    end

    many_to_many :service_instances, AshR2RML.Fortune5.ServiceInstance do
      through AshR2RML.Fortune5.DeploymentPlanService
      source_attribute_on_join_resource :deployment_plan_id
      destination_attribute_on_join_resource :service_instance_id
    end
  end
end

defmodule AshR2RML.Fortune5.DeploymentPlanService do
  @moduledoc """
  Join resource establishing many-to-many relationship between DeploymentPlans and ServiceInstances.
  """
  use Ash.Resource,
    domain: AshR2RML.Fortune5.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshR2RML]

  r2rml do
    class_iri("https://schema.org/Action")
    subject_template("https://deploy.fortune5.com/plan_services/{id}")
    table_name("fortune5_deployment_plan_services")

    attribute_mappings([
      {:traffic_weight, "https://w3id.org/fortune5/ontology#trafficWeight"}
    ])

    relationship_mappings([
      {:deployment_plan, "https://w3id.org/fortune5/ontology#partOfPlan"},
      {:service_instance, "https://w3id.org/fortune5/ontology#targetsService"}
    ])
  end

  attributes do
    uuid_primary_key :id
    attribute :traffic_weight, :integer, default: 100, public?: true
    attribute :deployment_plan_id, :uuid, allow_nil?: false, public?: true
    attribute :service_instance_id, :uuid, allow_nil?: false, public?: true
    timestamps()
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create do
      primary? true
      accept [:traffic_weight, :deployment_plan_id, :service_instance_id]
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  relationships do
    belongs_to :deployment_plan, AshR2RML.Fortune5.DeploymentPlan do
      source_attribute :deployment_plan_id
      destination_attribute :id
      attribute_writable? true
    end

    belongs_to :service_instance, AshR2RML.Fortune5.ServiceInstance do
      source_attribute :service_instance_id
      destination_attribute :id
      attribute_writable? true
    end
  end
end

defmodule AshR2RML.Fortune5.IncidentTicket do
  @moduledoc """
  Operational Incident Ticket resource with security-restricted confidential notes.
  """
  use Ash.Resource,
    domain: AshR2RML.Fortune5.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshR2RML]

  r2rml do
    class_iri("https://schema.org/Ticket")
    subject_template("https://ops.fortune5.com/incidents/{id}")
    table_name("fortune5_incident_tickets")

    attribute_mappings([
      {:ticket_number, "https://schema.org/identifier"},
      {:severity, "https://w3id.org/fortune5/ontology#severityLevel"},
      {:description, "https://schema.org/description"},
      {:status, "https://schema.org/status"},
      {:confidential_notes, "https://w3id.org/fortune5/ontology#confidentialOpsLog"}
    ])

    relationship_mappings([
      {:service_instance, "https://w3id.org/fortune5/ontology#affectsService"}
    ])
  end

  attributes do
    uuid_primary_key :id
    attribute :ticket_number, :string, allow_nil?: false, public?: true
    attribute :severity, AshR2RML.Fortune5.Types.CriticalityEnum, default: :high, public?: true
    attribute :description, :string, allow_nil?: false, public?: true

    attribute :status, :atom,
      constraints: [one_of: [:open, :investigating, :mitigated, :resolved]],
      default: :open,
      public?: true

    attribute :confidential_notes, :string, allow_nil?: true, public?: true
    attribute :service_instance_id, :uuid, allow_nil?: true, public?: true
    timestamps()
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create do
      primary? true
      accept [:ticket_number, :severity, :description, :status, :confidential_notes, :service_instance_id]
    end

    update :resolve do
      accept [:status, :confidential_notes]
      change set_attribute(:status, :resolved)
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  field_policies do
    # ODRL Policy: Confidential notes restricted to Security Officer and Admin
    field_policy [:confidential_notes] do
      authorize_if actor_attribute_equals(:role, :security_officer)
    end

    field_policy [:confidential_notes] do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    field_policy [:ticket_number, :severity, :description, :status, :service_instance_id] do
      authorize_if always()
    end
  end

  relationships do
    belongs_to :service_instance, AshR2RML.Fortune5.ServiceInstance do
      source_attribute :service_instance_id
      destination_attribute :id
      attribute_writable? true
    end
  end
end

defmodule AshR2RML.Fortune5.CredentialGrant do
  @moduledoc """
  W3C ODRL 2.0-aligned Credential and Access Permission Grant resource.
  """
  use Ash.Resource,
    domain: AshR2RML.Fortune5.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshR2RML]

  r2rml do
    class_iri("http://www.w3.org/ns/odrl/2/Permission")
    subject_template("https://auth.fortune5.com/grants/{id}")
    table_name("fortune5_credential_grants")

    attribute_mappings([
      {:grantee_id, "http://www.w3.org/ns/odrl/2/assignee"},
      {:role, "http://www.w3.org/ns/odrl/2/duty"},
      {:token_hash, "https://w3id.org/fortune5/ontology#tokenSignature"},
      {:active, "https://schema.org/active"},
      {:odrl_action, "http://www.w3.org/ns/odrl/2/action"}
    ])

    relationship_mappings([
      {:ledger_account, "http://www.w3.org/ns/odrl/2/target"}
    ])
  end

  attributes do
    uuid_primary_key :id
    attribute :grantee_id, :string, allow_nil?: false, public?: true

    attribute :role, :atom,
      constraints: [one_of: [:admin, :operator, :security_officer, :compliance_auditor, :viewer]],
      default: :viewer,
      public?: true

    attribute :token_hash, :string, allow_nil?: false, public?: true
    attribute :active, :boolean, default: true, public?: true
    attribute :odrl_action, :string, default: "http://www.w3.org/ns/odrl/2/read", public?: true
    attribute :ledger_account_id, :uuid, allow_nil?: true, public?: true
    timestamps()
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create do
      primary? true
      accept [:grantee_id, :role, :token_hash, :active, :odrl_action, :ledger_account_id]
    end

    update :revoke do
      accept [:active]
      change set_attribute(:active, false)
    end

    update :reactivate do
      accept [:active]
      change set_attribute(:active, true)
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  field_policies do
    # ODRL Policy: Cryptographic token hash restricted to Admin
    field_policy [:token_hash] do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    field_policy [:grantee_id, :role, :active, :odrl_action, :ledger_account_id] do
      authorize_if always()
    end
  end

  relationships do
    belongs_to :ledger_account, AshR2RML.Fortune5.LedgerAccount do
      source_attribute :ledger_account_id
      destination_attribute :id
      attribute_writable? true
    end
  end
end

defmodule AshR2RML.Fortune5.AshFactory do
  @moduledoc """
  Automated Ash system constructor reading semantic requirements and manufacturing dynamic
  Ash domains, resources, actions, calculations, custom types, relationships, and field-level
  authorization policies with ODRL correspondence.
  """

  alias AshR2RML.Fortune5.{
    CloudRegion,
    Cluster,
    CredentialGrant,
    DeploymentPlan,
    DeploymentPlanService,
    Domain,
    IncidentTicket,
    LedgerAccount,
    PaymentGateway,
    ServiceInstance
  }

  alias AshR2RML.Fortune5.Types.{CriticalityEnum, CurrencyAmount, IPAddressRange}

  @resources [
    CloudRegion,
    Cluster,
    ServiceInstance,
    PaymentGateway,
    LedgerAccount,
    DeploymentPlan,
    DeploymentPlanService,
    IncidentTicket,
    CredentialGrant
  ]

  @types [
    CurrencyAmount,
    IPAddressRange,
    CriticalityEnum
  ]

  @doc "Returns list of all admitted enterprise Fortune 5 resources."
  def resources, do: @resources

  @doc "Returns the Ash Domain containing all Fortune 5 resources."
  def domain, do: Domain

  @doc "Returns list of all Fortune 5 custom scalar types."
  def types, do: @types

  @doc "Compiles all Fortune 5 enterprise resources into a canonical AshR2RML Mapping Bundle."
  def compile_fortune5_bundle do
    AshR2RML.compile(@resources)
  end

  @doc "Renders W3C R2RML Turtle mapping for the entire Fortune 5 resource suite."
  def render_fortune5_r2rml do
    with {:ok, bundle} <- compile_fortune5_bundle() do
      AshR2RML.render(bundle)
    end
  end

  @doc """
  Builds and seeds a comprehensive in-memory test dataset across all enterprise resources in ETS.
  """
  def build_system_seed(opts \\ []) do
    region_code = Keyword.get(opts, :region_code, "us-east-1")

    # 1. Cloud Region
    {:ok, region} =
      CloudRegion
      |> Ash.Changeset.for_create(:create, %{
        name: "US East Primary Data Center",
        code: region_code,
        datacenter_location: "Ashburn, VA, USA",
        status: :active
      })
      |> Ash.create()

    # 2. Cluster
    {:ok, cluster} =
      Cluster
      |> Ash.Changeset.for_create(:create, %{
        name: "k8s-prod-alpha",
        ip_range: "10.100.0.0/16",
        criticality: :mission_critical,
        node_count: 32,
        cloud_region_id: region.id
      })
      |> Ash.create()

    # 3. Service Instances
    {:ok, service1} =
      ServiceInstance
      |> Ash.Changeset.for_create(:create, %{
        name: "billing-api",
        version: "2.4.1",
        endpoint_url: "https://billing.fortune5.internal/v2",
        status: :running,
        error_budget: Decimal.new("99.999"),
        cluster_id: cluster.id
      })
      |> Ash.create()

    {:ok, service2} =
      ServiceInstance
      |> Ash.Changeset.for_create(:create, %{
        name: "auth-gateway",
        version: "3.1.0",
        endpoint_url: "https://auth.fortune5.internal/v1",
        status: :running,
        error_budget: Decimal.new("99.995"),
        cluster_id: cluster.id
      })
      |> Ash.create()

    # 4. Payment Gateway
    {:ok, gateway} =
      PaymentGateway
      |> Ash.Changeset.for_create(:create, %{
        name: "Global High-Throughput Clearing Gateway",
        provider: "InternalClearHouse",
        api_endpoint: "https://clearing.fortune5.internal/api",
        secret_key: "sec_live_984f7281bc09a32",
        criticality: :mission_critical,
        status: :active,
        cloud_region_id: region.id
      })
      |> Ash.create()

    # 5. Ledger Account
    {:ok, account} =
      LedgerAccount
      |> Ash.Changeset.for_create(:create, %{
        account_number: "ACCT-9876543210",
        balance: %{amount: Decimal.new("50000000.00"), currency: "USD"},
        currency: "USD",
        risk_score: Decimal.new("0.01"),
        status: :active,
        payment_gateway_id: gateway.id
      })
      |> Ash.create()

    # 6. Deployment Plan
    {:ok, plan} =
      DeploymentPlan
      |> Ash.Changeset.for_create(:create, %{
        plan_code: "DEP-2026-Q3-001",
        target_version: "2.5.0",
        strategy: :blue_green,
        status: :in_progress,
        budget_limit: %{amount: Decimal.new("250000.00"), currency: "USD"},
        cluster_id: cluster.id
      })
      |> Ash.create()

    # 7. DeploymentPlanService (many-to-many join)
    {:ok, plan_service} =
      DeploymentPlanService
      |> Ash.Changeset.for_create(:create, %{
        traffic_weight: 100,
        deployment_plan_id: plan.id,
        service_instance_id: service1.id
      })
      |> Ash.create()

    # 8. Incident Ticket
    {:ok, incident} =
      IncidentTicket
      |> Ash.Changeset.for_create(:create, %{
        ticket_number: "INC-99014",
        severity: :high,
        description: "Elevated 5xx latency on billing-api checkout path",
        status: :investigating,
        confidential_notes: "Suspected redis connection pool starvation on pod replica 4",
        service_instance_id: service1.id
      })
      |> Ash.create()

    # 9. Credential Grant
    {:ok, grant} =
      CredentialGrant
      |> Ash.Changeset.for_create(:create, %{
        grantee_id: "sec-ops-bot-01",
        role: :security_officer,
        token_hash: "sha256:7f83b1657ff1fc53b92dc18148a1d65dfc2d4b1fa3d677284addd200126d9069",
        active: true,
        odrl_action: "http://www.w3.org/ns/odrl/2/read",
        ledger_account_id: account.id
      })
      |> Ash.create()

    %{
      region: region,
      cluster: cluster,
      services: [service1, service2],
      gateway: gateway,
      account: account,
      plan: plan,
      plan_service: plan_service,
      incident: incident,
      grant: grant
    }
  end
end
