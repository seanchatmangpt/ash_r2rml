# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GrandExample.Types.SemVer do
  @moduledoc """
  Custom Ash semantic version scalar type with standards-valid XSD datatype representation for test suites.
  """
  use Ash.Type

  use AshR2RML.Type,
    xsd_datatype: "http://www.w3.org/2001/XMLSchema#string"

  @impl Ash.Type
  def storage_type(_), do: :string

  @impl Ash.Type
  def cast_input(value, _) when is_binary(value), do: {:ok, value}
  def cast_input(%{major: maj, minor: min, patch: pat}, _), do: {:ok, "#{maj}.#{min}.#{pat}"}
  def cast_input(_, _), do: {:error, "Invalid SemVer format"}

  @impl Ash.Type
  def cast_stored(value, _), do: {:ok, to_string(value)}

  @impl Ash.Type
  def dump_to_native(value, _), do: {:ok, to_string(value)}

  @impl Ash.Type
  def dump_to_embedded(value, _), do: {:ok, to_string(value)}

  @impl AshR2RML.Type
  def to_rdf_lexical(value), do: "v#{value}"
end

defmodule AshR2RML.GrandExample.Domain do
  use Ash.Domain,
    validate_config_inclusion?: false

  resources do
    resource AshR2RML.GrandExample.Organization
    resource AshR2RML.GrandExample.Person
    resource AshR2RML.GrandExample.SemanticManifest
  end
end

defmodule AshR2RML.GrandExample.Organization do
  use Ash.Resource,
    domain: AshR2RML.GrandExample.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML]

  r2rml do
    class_iri("https://schema.org/Organization")
    subject_template("https://schema.org/Organization/{id}")
    table_name("schema_organizations")

    attribute_mappings([
      {:name, "https://schema.org/name"},
      {:version, "https://schema.org/version"}
    ])
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create do
      primary? true
      accept [:name, :version]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :version, AshR2RML.GrandExample.Types.SemVer, allow_nil?: false, public?: true
  end
end

defmodule AshR2RML.GrandExample.Person do
  use Ash.Resource,
    domain: AshR2RML.GrandExample.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML]

  r2rml do
    class_iri("https://schema.org/Person")
    subject_template("https://schema.org/Person/{id}")
    table_name("schema_people")

    attribute_mappings([
      {:name, "https://schema.org/name"},
      {:email, "https://schema.org/email"}
    ])
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create do
      primary? true
      accept [:name, :email, :organization_id]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :email, :string, allow_nil?: false, public?: true
    attribute :organization_id, :uuid, allow_nil?: true, public?: true
  end

  relationships do
    belongs_to :organization, AshR2RML.GrandExample.Organization do
      source_attribute :organization_id
      destination_attribute :id
      attribute_writable? true
    end
  end
end

defmodule AshR2RML.GrandExample.SemanticManifest do
  use Ash.Resource,
    domain: AshR2RML.GrandExample.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML]

  r2rml do
    class_iri("https://schema.org/Dataset")
    subject_template("https://schema.org/Dataset/{id}")
    table_name("schema_datasets")

    attribute_mappings([
      {:title, "https://schema.org/headline"},
      {:status, "https://schema.org/creativeWorkStatus"},
      {:published_turtle, "https://schema.org/text"}
    ])
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, allow_nil?: false, public?: true
    attribute :status, :atom, default: :draft, constraints: [one_of: [:draft, :published, :archived]], public?: true
    attribute :published_turtle, :string, allow_nil?: true, public?: true
    timestamps()
  end

  actions do
    defaults [:read, :destroy]

    create :create_manifest do
      primary? true
      accept [:title, :status, :published_turtle]
    end

    update :mark_published do
      accept [:status, :published_turtle]
      change set_attribute(:status, :published)
    end

    update :revert_status do
      accept [:status]
      change set_attribute(:status, :draft)
    end
  end
end
