# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.POWL.Ash.ProcessModel do
  @moduledoc "Ash Resource for a Workflow Process Model mapped to powl:Model"
  use Ash.Resource,
    domain: AshR2RML.POWL.Ash.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML]

  r2rml do
    class_iri("https://w3id.org/powl/v2#Model")
    subject_template("https://example.org/process/model/{id}")
    table_name("powl_process_models")

    attribute_mappings(
      name: "http://www.w3.org/2000/01/rdf-schema#label",
      root_type: "https://w3id.org/powl/v2#nodeType",
      raw_owl_turtle: "https://w3id.org/powl/v2#serializedOntology"
    )
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :root_type, :string do
      allow_nil? true
      public? true
    end

    attribute :raw_owl_turtle, :string do
      allow_nil? true
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :transitions, AshR2RML.POWL.Ash.Transition, destination_attribute: :process_model_id
    has_many :places, AshR2RML.POWL.Ash.Place, destination_attribute: :process_model_id
    has_many :flow_arcs, AshR2RML.POWL.Ash.FlowArc, destination_attribute: :process_model_id
    has_many :decomposed_nodes, AshR2RML.POWL.Ash.DecomposedNode, destination_attribute: :process_model_id
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:id, :name, :root_type, :raw_owl_turtle]
    end

    update :update do
      primary? true
      accept [:name, :root_type, :raw_owl_turtle]
    end
  end
end

defmodule AshR2RML.POWL.Ash.Transition do
  @moduledoc "Ash Resource for a Workflow Transition mapped to powl:Transition"
  use Ash.Resource,
    domain: AshR2RML.POWL.Ash.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML]

  r2rml do
    class_iri("https://w3id.org/powl/v2#Transition")
    subject_template("https://example.org/process/transition/{id}")
    table_name("powl_transitions")

    attribute_mappings(
      label: "https://w3id.org/powl/v2#activityLabel",
      key_name: "http://www.w3.org/2000/01/rdf-schema#label",
      silent?: "https://w3id.org/powl/v2#isSilent"
    )
  end

  attributes do
    uuid_primary_key :id

    attribute :process_model_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :key_name, :string do
      allow_nil? false
      public? true
    end

    attribute :label, :string do
      allow_nil? false
      public? true
    end

    attribute :silent?, :boolean do
      default false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :process_model, AshR2RML.POWL.Ash.ProcessModel, source_attribute: :process_model_id
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:id, :process_model_id, :key_name, :label, :silent?]
    end
  end
end

defmodule AshR2RML.POWL.Ash.Place do
  @moduledoc "Ash Resource for a Workflow Place mapped to powl:Place"
  use Ash.Resource,
    domain: AshR2RML.POWL.Ash.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML]

  r2rml do
    class_iri("https://w3id.org/powl/v2#Place")
    subject_template("https://example.org/process/place/{id}")
    table_name("powl_places")

    attribute_mappings(
      name: "http://www.w3.org/2000/01/rdf-schema#label",
      is_source?: "https://w3id.org/powl/v2#isSource",
      is_sink?: "https://w3id.org/powl/v2#isSink"
    )
  end

  attributes do
    uuid_primary_key :id

    attribute :process_model_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :is_source?, :boolean do
      default false
      public? true
    end

    attribute :is_sink?, :boolean do
      default false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :process_model, AshR2RML.POWL.Ash.ProcessModel, source_attribute: :process_model_id
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:id, :process_model_id, :name, :is_source?, :is_sink?]
    end
  end
end

defmodule AshR2RML.POWL.Ash.FlowArc do
  @moduledoc "Ash Resource for a Flow Arc between Place and Transition"
  use Ash.Resource,
    domain: AshR2RML.POWL.Ash.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML]

  r2rml do
    class_iri("https://w3id.org/powl/v2#FlowArc")
    subject_template("https://example.org/process/flow/{id}")
    table_name("powl_flow_arcs")

    attribute_mappings(
      source_name: "https://w3id.org/powl/v2#sourceName",
      target_name: "https://w3id.org/powl/v2#targetName"
    )
  end

  attributes do
    uuid_primary_key :id

    attribute :process_model_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :source_name, :string do
      allow_nil? false
      public? true
    end

    attribute :target_name, :string do
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :process_model, AshR2RML.POWL.Ash.ProcessModel, source_attribute: :process_model_id
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:id, :process_model_id, :source_name, :target_name]
    end
  end
end

defmodule AshR2RML.POWL.Ash.DecomposedNode do
  @moduledoc "Ash Resource for Decomposed POWL 2.0 Nodes (ChoiceGraph / PartialOrder)"
  use Ash.Resource,
    domain: AshR2RML.POWL.Ash.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML]

  r2rml do
    class_iri("https://w3id.org/powl/v2#DecomposedNode")
    subject_template("https://example.org/process/decomposed/{id}")
    table_name("powl_decomposed_nodes")

    attribute_mappings(
      node_type: "https://w3id.org/powl/v2#nodeType",
      label: "http://www.w3.org/2000/01/rdf-schema#label",
      spec_json: "https://w3id.org/powl/v2#specJson"
    )
  end

  attributes do
    uuid_primary_key :id

    attribute :process_model_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :node_type, :string do
      allow_nil? false
      public? true
    end

    attribute :label, :string do
      allow_nil? true
      public? true
    end

    attribute :spec_json, :string do
      allow_nil? true
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :process_model, AshR2RML.POWL.Ash.ProcessModel, source_attribute: :process_model_id
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:id, :process_model_id, :node_type, :label, :spec_json]
    end
  end
end

defmodule AshR2RML.POWL.Ash.Domain do
  @moduledoc "Ash Domain for POWL 2.0 Process Models and Workflow Components"
  use Ash.Domain

  resources do
    resource AshR2RML.POWL.Ash.ProcessModel
    resource AshR2RML.POWL.Ash.Transition
    resource AshR2RML.POWL.Ash.Place
    resource AshR2RML.POWL.Ash.FlowArc
    resource AshR2RML.POWL.Ash.DecomposedNode
  end
end
