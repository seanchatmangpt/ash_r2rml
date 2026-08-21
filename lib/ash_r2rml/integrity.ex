# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Integrity.Canonical do
  @moduledoc false

  def term(%_{} = struct), do: struct |> Map.from_struct() |> term()

  def term(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> {term(key), term(value)} end)
    |> Enum.sort_by(fn {key, _value} -> :erlang.term_to_binary(key, [:deterministic]) end)
  end

  def term(list) when is_list(list), do: Enum.map(list, &term/1)
  def term(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> Enum.map(&term/1)
  def term(other), do: other

  def sha256(value) do
    value
    |> term()
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  def binary_sha256(value) when is_binary(value) do
    :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
  end
end

defmodule AshR2RML.SemanticSessionIdentity do
  @moduledoc """
  Content-addressed identity for the exact admitted semantic compilation subject.

  A compilation receipt is reusable only when this identity matches exactly.
  External environments may be bound later, but binding creates a new identity;
  it never mutates the meaning of an already-issued compilation receipt.
  """

  alias AshR2RML.Integrity.Canonical
  alias AshR2RML.Refusal

  defstruct [
    :sha256,
    :ontology_hash,
    :profile_hash,
    :shacl_hash,
    :ir_sha256,
    :mapping_sha256,
    :compiler_module_sha256,
    :compiler_version,
    :elixir_version,
    :otp_release,
    postgres: nil,
    obda: nil,
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          sha256: String.t(),
          ontology_hash: String.t() | nil,
          profile_hash: String.t() | nil,
          shacl_hash: String.t() | nil,
          ir_sha256: String.t() | nil,
          mapping_sha256: String.t() | nil,
          compiler_module_sha256: String.t() | nil,
          compiler_version: String.t() | nil,
          elixir_version: String.t(),
          otp_release: String.t(),
          postgres: map() | nil,
          obda: map() | nil,
          metadata: map()
        }

  @spec new(map() | keyword()) :: t()
  def new(attrs) do
    attrs = Map.new(attrs)

    identity = %__MODULE__{
      ontology_hash: get(attrs, :ontology_hash),
      profile_hash: get(attrs, :profile_hash),
      shacl_hash: get(attrs, :shacl_hash),
      ir_sha256: get(attrs, :ir_sha256),
      mapping_sha256: get(attrs, :mapping_sha256),
      compiler_module_sha256:
        get(attrs, :compiler_module_sha256) || module_sha256(AshR2RML.Compiler),
      compiler_version: get(attrs, :compiler_version) || app_version(),
      elixir_version: get(attrs, :elixir_version) || System.version(),
      otp_release: get(attrs, :otp_release) || System.otp_release(),
      postgres: get(attrs, :postgres),
      obda: get(attrs, :obda),
      metadata: get(attrs, :metadata, %{})
    }

    %{identity | sha256: identity_hash(identity)}
  end

  @spec bind_environment(t(), map() | keyword()) :: t()
  def bind_environment(%__MODULE__{} = identity, attrs) do
    attrs = Map.new(attrs)

    identity
    |> Map.from_struct()
    |> Map.drop([:sha256])
    |> Map.put(:postgres, get(attrs, :postgres, identity.postgres))
    |> Map.put(:obda, get(attrs, :obda, identity.obda))
    |> Map.put(:metadata, Map.merge(identity.metadata, get(attrs, :metadata, %{})))
    |> new()
  end

  @spec matches?(t(), t()) :: boolean()
  def matches?(%__MODULE__{sha256: left}, %__MODULE__{sha256: right}), do: left == right

  @spec admit_reuse(t(), t()) :: {:ok, :identical} | {:error, Refusal.t()}
  def admit_reuse(%__MODULE__{} = expected, %__MODULE__{} = observed) do
    if matches?(expected, observed) do
      {:ok, :identical}
    else
      {:error,
       Refusal.new(
         :REFUSED_SESSION_IDENTITY_MISMATCH,
         :semantic_session,
         "semantic-session identity does not match the admitted receipt subject",
         %{expected_sha256: expected.sha256, observed_sha256: observed.sha256}
       )}
    end
  end

  @spec module_sha256(module()) :: String.t() | nil
  def module_sha256(module) when is_atom(module) do
    case :code.get_object_code(module) do
      {^module, beam, _path} when is_binary(beam) -> Canonical.binary_sha256(beam)
      _ -> nil
    end
  end

  defp identity_hash(identity) do
    identity
    |> Map.from_struct()
    |> Map.drop([:sha256])
    |> Canonical.sha256()
  end

  defp app_version do
    case Application.spec(:ash_neo4j, :vsn) do
      nil -> nil
      version -> to_string(version)
    end
  end

  defp get(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end
end

defmodule AshR2RML.Proof do
  @moduledoc "Typed proof classes. A lower checkpoint never implies a higher standing."

  @classes [
    :mapping_admitted,
    :projections_deterministic,
    :relational_observed,
    :obda_query_observed,
    :subject_identity_verified,
    :result_parity_verified,
    :ontology_roundtrip_verified
  ]

  @requirements %{
    mapping_admitted: [:mapping_admitted],
    projections_deterministic: [:mapping_admitted, :projections_deterministic],
    relational_alive: [:mapping_admitted, :projections_deterministic, :relational_observed],
    obda_alive: [:mapping_admitted, :projections_deterministic, :relational_observed, :obda_query_observed],
    subject_parity_alive: [
      :mapping_admitted,
      :projections_deterministic,
      :relational_observed,
      :obda_query_observed,
      :subject_identity_verified,
      :result_parity_verified
    ],
    ontology_roundtrip_alive: @classes
  }

  @spec classes() :: [atom()]
  def classes, do: @classes

  @spec add([atom()], atom()) :: [atom()]
  def add(proofs, proof) when proof in @classes, do: Enum.uniq(proofs ++ [proof])
  def add(proofs, _unknown), do: proofs

  @spec achieved?([atom()], atom()) :: boolean()
  def achieved?(proofs, standing) do
    required = Map.get(@requirements, standing, [])
    required != [] and Enum.all?(required, &(&1 in proofs))
  end

  @spec highest([atom()]) :: atom()
  def highest(proofs) do
    cond do
      achieved?(proofs, :ontology_roundtrip_alive) -> :ontology_roundtrip_alive
      achieved?(proofs, :subject_parity_alive) -> :subject_parity_alive
      achieved?(proofs, :obda_alive) -> :obda_alive
      achieved?(proofs, :relational_alive) -> :relational_alive
      achieved?(proofs, :projections_deterministic) -> :projections_deterministic
      achieved?(proofs, :mapping_admitted) -> :mapping_admitted
      true -> :unknown
    end
  end
end

defmodule AshR2RML.Bounds do
  @moduledoc "Fail-closed resource bounds for normalized ontology/profile admission."

  alias AshR2RML.Refusal

  @defaults %{
    max_resources: 2_048,
    max_attributes_per_resource: 2_048,
    max_relationships_per_resource: 2_048,
    max_actions_per_resource: 1_024,
    max_policies_per_resource: 1_024,
    max_total_members: 250_000,
    max_input_bytes: 64 * 1024 * 1024,
    max_ontology_triples: 2_000_000,
    max_shapes: 250_000
  }

  @spec defaults() :: map()
  def defaults, do: @defaults

  @spec admit_input(term(), keyword() | map()) :: :ok | {:error, Refusal.t()}
  def admit_input(input, opts \\ []) do
    configured = get_option(opts, :max_input_bytes, @defaults.max_input_bytes)
    limit = if is_integer(configured) and configured >= 0, do: configured, else: @defaults.max_input_bytes
    bytes = input_bytes(input)

    if bytes <= limit do
      :ok
    else
      {:error,
       Refusal.new(
         :REFUSED_RESOURCE_BOUND,
         :semantic_input,
         "semantic input exceeded the configured byte bound",
         %{bound: :max_input_bytes, observed: bytes, limit: limit}
       )}
    end
  end

  @spec admit_profile(map()) :: :ok | {:error, Refusal.t()}
  def admit_profile(profile) when is_map(profile) do
    limits = normalized_limits(get(profile, :bounds, %{}))
    resources = List.wrap(get(profile, :resources, []))

    counts = %{
      resources: length(resources),
      max_attributes_per_resource: max_nested(resources, :attributes),
      max_relationships_per_resource: max_nested(resources, :relationships),
      max_actions_per_resource: max_nested(resources, :actions),
      max_policies_per_resource: max_nested(resources, :policies),
      total_members: total_members(resources),
      input_bytes: integer_or_zero(get(profile, :input_bytes)),
      ontology_triples: integer_or_zero(get(profile, :ontology_triples)),
      shapes: integer_or_zero(get(profile, :shape_count))
    }

    checks = [
      {:max_resources, counts.resources},
      {:max_attributes_per_resource, counts.max_attributes_per_resource},
      {:max_relationships_per_resource, counts.max_relationships_per_resource},
      {:max_actions_per_resource, counts.max_actions_per_resource},
      {:max_policies_per_resource, counts.max_policies_per_resource},
      {:max_total_members, counts.total_members},
      {:max_input_bytes, counts.input_bytes},
      {:max_ontology_triples, counts.ontology_triples},
      {:max_shapes, counts.shapes}
    ]

    case Enum.find(checks, fn {limit_key, observed} -> observed > Map.fetch!(limits, limit_key) end) do
      nil ->
        :ok

      {limit_key, observed} ->
        {:error,
         Refusal.new(
           :REFUSED_RESOURCE_BOUND,
           :profile,
           "semantic admission exceeded a configured resource bound",
           %{bound: limit_key, observed: observed, limit: Map.fetch!(limits, limit_key)}
         )}
    end
  end

  def admit_profile(_other) do
    {:error,
     Refusal.new(
       :REFUSED_RESOURCE_BOUND,
       :profile,
       "semantic bounds require a normalized profile map",
       %{}
     )}
  end

  defp normalized_limits(overrides) when is_map(overrides) do
    Enum.reduce(@defaults, @defaults, fn {key, default}, acc ->
      value = get(overrides, key, default)
      Map.put(acc, key, if(is_integer(value) and value >= 0, do: value, else: default))
    end)
  end

  defp normalized_limits(_), do: @defaults

  defp max_nested(resources, key) do
    resources
    |> Enum.map(fn resource -> resource |> get(key, []) |> List.wrap() |> length() end)
    |> Enum.max(fn -> 0 end)
  end

  defp total_members(resources) do
    Enum.reduce(resources, 0, fn resource, acc ->
      acc +
        Enum.sum(
          for key <- [:attributes, :relationships, :actions, :policies] do
            resource |> get(key, []) |> List.wrap() |> length()
          end
        )
    end)
  end

  defp input_bytes(value) when is_binary(value), do: byte_size(value)

  defp input_bytes(value) do
    case Jason.encode(value) do
      {:ok, encoded} -> byte_size(encoded)
      {:error, _reason} -> byte_size(:erlang.term_to_binary(value, [:deterministic]))
    end
  end

  defp get_option(opts, key, default) when is_list(opts), do: Keyword.get(opts, key, default)
  defp get_option(opts, key, default) when is_map(opts), do: get(opts, key, default)
  defp get_option(_opts, _key, default), do: default

  defp integer_or_zero(value) when is_integer(value) and value >= 0, do: value
  defp integer_or_zero(_), do: 0

  defp get(map, key, default \\ nil) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end
end

defmodule AshR2RML.SemanticValue do
  @moduledoc "Explicit semantic absence algebra for SQL/RDF/Ash correspondence."

  @kinds [:value, :null, :unbound, :not_asserted, :unknown, :not_projected, :unsupported, :refused]
  @enforce_keys [:kind]
  defstruct [:kind, :value, :reason]

  @type kind :: :value | :null | :unbound | :not_asserted | :unknown | :not_projected | :unsupported | :refused
  @type t :: %__MODULE__{kind: kind(), value: term(), reason: term()}

  def value(value), do: %__MODULE__{kind: :value, value: value}
  def null, do: %__MODULE__{kind: :null}
  def unbound, do: %__MODULE__{kind: :unbound}
  def not_asserted, do: %__MODULE__{kind: :not_asserted}
  def unknown(reason \\ nil), do: %__MODULE__{kind: :unknown, reason: reason}
  def not_projected(reason \\ nil), do: %__MODULE__{kind: :not_projected, reason: reason}
  def unsupported(reason \\ nil), do: %__MODULE__{kind: :unsupported, reason: reason}
  def refused(reason), do: %__MODULE__{kind: :refused, reason: reason}

  def kind(%__MODULE__{kind: kind}) when kind in @kinds, do: kind
end

defmodule AshR2RML.SemanticDrift do
  @moduledoc """
  DfCM drift calculus between two admitted SemanticIR values.

  Exact receipt reuse is deliberately stricter than migration compatibility:
  only `:identical` admits receipt reuse. Representation changes remain lawful
  possibilities, but require fresh construction and parity evidence.
  """

  alias AshR2RML.Integrity.Canonical
  alias AshR2RML.SemanticIR

  @enforce_keys [:classification, :changes, :old_sha256, :new_sha256]
  defstruct [
    :classification,
    :changes,
    :old_sha256,
    :new_sha256,
    receipt_reusable?: false,
    forward_compatible?: false
  ]

  @type classification ::
          :identical
          | :additive
          | :compatible
          | :representation_change
          | :identity_affecting
          | :destructive
          | :ambiguous

  @type t :: %__MODULE__{
          classification: classification(),
          changes: [map()],
          old_sha256: String.t(),
          new_sha256: String.t(),
          receipt_reusable?: boolean(),
          forward_compatible?: boolean()
        }

  @spec compare(SemanticIR.t(), SemanticIR.t()) :: t()
  def compare(%SemanticIR{} = old, %SemanticIR{} = new) do
    old_sha = Canonical.sha256(old)
    new_sha = Canonical.sha256(new)

    with {:ok, old_by_class} <- index_resources(old.resources),
         {:ok, new_by_class} <- index_resources(new.resources) do
      changes = compare_resources(old_by_class, new_by_class)
      classification = classify(changes)

      %__MODULE__{
        classification: classification,
        changes: changes,
        old_sha256: old_sha,
        new_sha256: new_sha,
        receipt_reusable?: classification == :identical,
        forward_compatible?: classification in [:identical, :additive, :compatible]
      }
    else
      {:error, changes} ->
        %__MODULE__{
          classification: :ambiguous,
          changes: changes,
          old_sha256: old_sha,
          new_sha256: new_sha,
          receipt_reusable?: false,
          forward_compatible?: false
        }
    end
  end

  defp index_resources(resources) do
    Enum.reduce_while(resources, {:ok, %{}}, fn resource, {:ok, acc} ->
      key = resource.class_iri

      if is_binary(key) and not Map.has_key?(acc, key) do
        {:cont, {:ok, Map.put(acc, key, resource)}}
      else
        {:halt,
         {:error,
          [
            change(
              :ambiguous_resource_identity,
              key || :missing_class_iri,
              :ambiguous,
              %{reason: :duplicate_or_missing_class_iri}
            )
          ]}}
      end
    end)
  end

  defp compare_resources(old, new) do
    (Map.keys(old) ++ Map.keys(new))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.flat_map(fn class_iri ->
      case {Map.get(old, class_iri), Map.get(new, class_iri)} do
        {nil, resource} ->
          [change(:resource_added, class_iri, :additive, %{module: resource.module})]

        {resource, nil} ->
          [change(:resource_removed, class_iri, :destructive, %{module: resource.module})]

        {left, right} ->
          compare_resource(left, right)
      end
    end)
  end

  defp compare_resource(left, right) do
    identity =
      if left.subject_template != right.subject_template or
           Canonical.term(left.identities) != Canonical.term(right.identities) do
        [
          change(:semantic_identity_changed, left.class_iri, :identity_affecting, %{
            old_subject_template: left.subject_template,
            new_subject_template: right.subject_template
          })
        ]
      else
        []
      end

    representation =
      if {left.module, left.repo_module, left.table} != {right.module, right.repo_module, right.table} do
        [
          change(:resource_representation_changed, left.class_iri, :representation_change, %{
            old: {left.module, left.repo_module, left.table},
            new: {right.module, right.repo_module, right.table}
          })
        ]
      else
        []
      end

    behavior =
      if Canonical.term({left.actions, left.policies}) != Canonical.term({right.actions, right.policies}) do
        [change(:behavior_contract_changed, left.class_iri, :compatible, %{})]
      else
        []
      end

    identity ++
      representation ++
      compare_attributes(left.class_iri, left.attributes, right.attributes) ++
      compare_relationships(left.class_iri, left.relationships, right.relationships) ++ behavior
  end

  defp compare_attributes(class_iri, old_attrs, new_attrs) do
    old = Map.new(old_attrs, &{&1.name, &1})
    new = Map.new(new_attrs, &{&1.name, &1})

    union_keys(old, new)
    |> Enum.flat_map(fn name ->
      case {Map.get(old, name), Map.get(new, name)} do
        {nil, attribute} ->
          severity = if attribute.min_count > 0, do: :destructive, else: :additive
          [change(:attribute_added, {class_iri, name}, severity, %{min_count: attribute.min_count})]

        {attribute, nil} ->
          [change(:attribute_removed, {class_iri, name}, :destructive, %{predicate_iri: attribute.predicate_iri})]

        {left, right} ->
          compare_attribute({class_iri, name}, left, right)
      end
    end)
  end

  defp compare_attribute(subject, left, right) do
    semantic =
      if {left.predicate_iri, left.datatype_iri} != {right.predicate_iri, right.datatype_iri} do
        [
          change(:attribute_semantics_changed, subject, :destructive, %{
            old: {left.predicate_iri, left.datatype_iri},
            new: {right.predicate_iri, right.datatype_iri}
          })
        ]
      else
        []
      end

    identity =
      if left.identity? != right.identity? do
        [change(:attribute_identity_membership_changed, subject, :identity_affecting, %{})]
      else
        []
      end

    cardinality = cardinality_change(subject, left.min_count, left.max_count, right.min_count, right.max_count)

    representation =
      if {left.column, left.ash_type, left.postgres_type, left.nullable} !=
           {right.column, right.ash_type, right.postgres_type, right.nullable} do
        [
          change(:attribute_representation_changed, subject, :representation_change, %{
            old: {left.column, left.ash_type, left.postgres_type, left.nullable},
            new: {right.column, right.ash_type, right.postgres_type, right.nullable}
          })
        ]
      else
        []
      end

    semantic ++ identity ++ cardinality ++ representation
  end

  defp compare_relationships(class_iri, old_rels, new_rels) do
    old = Map.new(old_rels, &{&1.name, &1})
    new = Map.new(new_rels, &{&1.name, &1})

    union_keys(old, new)
    |> Enum.flat_map(fn name ->
      case {Map.get(old, name), Map.get(new, name)} do
        {nil, relationship} ->
          severity = if relationship.min_count > 0, do: :destructive, else: :additive
          [change(:relationship_added, {class_iri, name}, severity, %{min_count: relationship.min_count})]

        {relationship, nil} ->
          [
            change(:relationship_removed, {class_iri, name}, :destructive, %{
              predicate_iri: relationship.predicate_iri
            })
          ]

        {left, right} ->
          compare_relationship({class_iri, name}, left, right)
      end
    end)
  end

  defp compare_relationship(subject, left, right) do
    semantic =
      if {left.predicate_iri, left.inverse_predicate, left.source_class, left.target_class} !=
           {right.predicate_iri, right.inverse_predicate, right.source_class, right.target_class} do
        [change(:relationship_semantics_changed, subject, :destructive, %{})]
      else
        []
      end

    cardinality = cardinality_change(subject, left.min_count, left.max_count, right.min_count, right.max_count)

    representation_fields = [
      :storage_strategy,
      :storage_candidates,
      :source_key,
      :destination_key,
      :join_table,
      :source_join_column,
      :destination_join_column,
      :association_resource
    ]

    representation_changed? =
      Enum.any?(representation_fields, fn field -> Map.get(left, field) != Map.get(right, field) end)

    representation =
      if representation_changed? do
        [change(:relationship_representation_changed, subject, :representation_change, %{})]
      else
        []
      end

    semantic ++ cardinality ++ representation
  end

  defp cardinality_change(subject, old_min, old_max, new_min, new_max) do
    cond do
      new_min > old_min or narrower_max?(old_max, new_max) ->
        [
          change(:cardinality_tightened, subject, :destructive, %{
            old: {old_min, old_max},
            new: {new_min, new_max}
          })
        ]

      new_min < old_min or wider_max?(old_max, new_max) ->
        [
          change(:cardinality_relaxed, subject, :compatible, %{
            old: {old_min, old_max},
            new: {new_min, new_max}
          })
        ]

      true ->
        []
    end
  end

  defp narrower_max?(nil, new) when is_integer(new), do: true
  defp narrower_max?(old, new) when is_integer(old) and is_integer(new), do: new < old
  defp narrower_max?(_, _), do: false

  defp wider_max?(old, nil) when is_integer(old), do: true
  defp wider_max?(old, new) when is_integer(old) and is_integer(new), do: new > old
  defp wider_max?(_, _), do: false

  defp union_keys(left, right), do: (Map.keys(left) ++ Map.keys(right)) |> Enum.uniq() |> Enum.sort()

  defp classify([]), do: :identical

  defp classify(changes) do
    severities = Enum.map(changes, & &1.severity)

    cond do
      :ambiguous in severities -> :ambiguous
      :identity_affecting in severities -> :identity_affecting
      :destructive in severities -> :destructive
      :representation_change in severities -> :representation_change
      :compatible in severities -> :compatible
      true -> :additive
    end
  end

  defp change(kind, subject, severity, details) do
    %{kind: kind, subject: subject, severity: severity, details: details}
  end
end

defmodule AshR2RML.DfCM.IncrementalPlan do
  @moduledoc "Content-addressed reuse plan; it never grants execution or publication authority."

  defstruct [
    :mode,
    :old_session_sha256,
    :new_session_sha256,
    :drift_classification,
    reusable_resource_classes: [],
    changed_resource_classes: [],
    blocked: []
  ]

  @type t :: %__MODULE__{
          mode: :reuse_exact_receipt | :recompile,
          old_session_sha256: String.t(),
          new_session_sha256: String.t(),
          drift_classification: AshR2RML.SemanticDrift.classification(),
          reusable_resource_classes: [String.t()],
          changed_resource_classes: [String.t()],
          blocked: [atom()]
        }
end

defmodule AshR2RML.OBDA.CapabilityReceipt do
  @moduledoc "Bounded capability-admission receipt for an external OBDA engine."
  defstruct [
    :engine,
    :version,
    :standard_valid?,
    :engine_supported?,
    :executed?,
    :receipt_sha256,
    required: [],
    supported: [],
    missing: []
  ]

  @type t :: %__MODULE__{
          engine: atom() | String.t(),
          version: String.t() | nil,
          standard_valid?: boolean(),
          engine_supported?: boolean(),
          executed?: boolean(),
          receipt_sha256: String.t() | nil,
          required: [atom()],
          supported: [atom()],
          missing: [atom()]
        }
end

defmodule AshR2RML.OBDA.Capabilities do
  @moduledoc "Separates W3C mapping validity from engine support and observed execution."

  alias AshR2RML.Integrity.Canonical
  alias AshR2RML.OBDA.CapabilityReceipt
  alias AshR2RML.Refusal

  @w3c [
    :table_name,
    :sql_query,
    :subject_template,
    :column_object_map,
    :constant_object_map,
    :reference_object_map,
    :join_condition,
    :named_graph,
    :blank_node,
    :language_map,
    :datatype_map
  ]

  @ontop_conservative [
    :table_name,
    :subject_template,
    :column_object_map,
    :reference_object_map,
    :join_condition,
    :datatype_map
  ]

  @spec supported(atom() | String.t(), String.t() | nil) :: [atom()]
  def supported(engine, version \\ nil)

  def supported(engine, version) when engine in [:ontop, "ontop"] do
    case version do
      nil -> @ontop_conservative
      value when is_binary(value) -> ontop_supported(value)
      _ -> @ontop_conservative
    end
  end

  def supported(_engine, _version), do: []

  @spec admit(atom() | String.t(), String.t() | nil, [atom()]) ::
          {:ok, CapabilityReceipt.t()} | {:error, Refusal.t()}
  def admit(engine, version, required) when is_list(required) do
    supported = supported(engine, version)
    unknown_standard = required -- @w3c
    missing = required -- supported

    cond do
      engine not in [:ontop, "ontop"] ->
        {:error,
         Refusal.new(
           :REFUSED_OBDA_CAPABILITY,
           engine,
           "OBDA engine is outside the admitted capability registry",
           %{version: version}
         )}

      unknown_standard != [] ->
        {:error,
         Refusal.new(
           :REFUSED_OBDA_CAPABILITY,
           engine,
           "requested capability is outside the admitted R2RML capability vocabulary",
           %{capabilities: unknown_standard}
         )}

      missing != [] ->
        {:error,
         Refusal.new(
           :REFUSED_OBDA_CAPABILITY,
           engine,
           "OBDA engine does not admit every required mapping capability",
           %{version: version, missing: missing}
         )}

      true ->
        receipt = %CapabilityReceipt{
          engine: engine,
          version: version,
          standard_valid?: true,
          engine_supported?: true,
          executed?: false,
          required: Enum.sort(required),
          supported: Enum.sort(supported),
          missing: []
        }

        {:ok, seal(receipt)}
    end
  end

  def mark_executed(%CapabilityReceipt{} = receipt), do: seal(%{receipt | executed?: true})

  defp ontop_supported(version) do
    case Version.parse(version) do
      {:ok, parsed} ->
        case Version.compare(parsed, Version.parse!("5.5.0")) do
          relation when relation in [:eq, :gt] -> @w3c
          :lt -> @ontop_conservative
        end

      :error ->
        @ontop_conservative
    end
  end

  defp seal(receipt) do
    hash = receipt |> Map.from_struct() |> Map.drop([:receipt_sha256]) |> Canonical.sha256()
    %{receipt | receipt_sha256: hash}
  end
end

defmodule AshR2RML.Manufacturing.Plan do
  @moduledoc "CONSTRUCT-only atomic-publication plan consumed by ggen."
  defstruct [
    :status,
    :standing,
    :session_sha256,
    :manifest_sha256,
    :stage_id,
    ordered_paths: [],
    file_hashes: %{},
    protocol: []
  ]

  @type t :: %__MODULE__{
          status: atom(),
          standing: atom(),
          session_sha256: String.t() | nil,
          manifest_sha256: String.t(),
          stage_id: String.t(),
          ordered_paths: [String.t()],
          file_hashes: map(),
          protocol: [atom()]
        }
end

defmodule AshR2RML.Manufacturing.VerificationReceipt do
  @moduledoc "Receipt proving that an externally staged file set matches a manufacturing plan."
  defstruct [
    :status,
    :standing,
    :manifest_sha256,
    :observed_manifest_sha256,
    :receipt_sha256,
    verified?: false,
    missing: [],
    extra: [],
    mismatched: []
  ]

  @type t :: %__MODULE__{
          status: atom(),
          standing: atom(),
          manifest_sha256: String.t(),
          observed_manifest_sha256: String.t(),
          receipt_sha256: String.t(),
          verified?: boolean(),
          missing: [String.t()],
          extra: [String.t()],
          mismatched: [String.t()]
        }
end

defmodule AshR2RML.Manufacturing do
  @moduledoc """
  Manufactures deterministic atomic-publication plans without writing files.

  ggen remains the filesystem authority. It stages an isolated tree, reports the
  observed content hashes here, and only an exact verification receipt is fit to
  accompany an atomic publish. A partial stage can never be mistaken for the
  previous or next admitted artifact set.
  """

  alias AshR2RML.Integrity.Canonical
  alias AshR2RML.Manufacturing.{Plan, VerificationReceipt}
  alias AshR2RML.Refusal

  @protocol [
    :write_isolated_stage,
    :sync_stage_or_equivalent,
    :verify_exact_file_hashes,
    :atomic_publish,
    :persist_verification_receipt
  ]

  @spec plan(map(), AshR2RML.SemanticSessionIdentity.t() | nil) :: Plan.t()
  def plan(files, session_identity \\ nil) when is_map(files) do
    file_hashes =
      files
      |> Enum.map(fn {path, content} -> {path, Canonical.sha256(content)} end)
      |> Enum.sort_by(&elem(&1, 0))
      |> Map.new()

    manifest_sha256 = Canonical.sha256(file_hashes)

    %Plan{
      status: :PARTIAL_ALIVE,
      standing: :construct_only,
      session_sha256: session_identity && session_identity.sha256,
      manifest_sha256: manifest_sha256,
      stage_id: "ash-r2rml-" <> String.slice(manifest_sha256, 0, 20),
      ordered_paths: file_hashes |> Map.keys() |> Enum.sort(),
      file_hashes: file_hashes,
      protocol: @protocol
    }
  end

  @spec verify_staged(Plan.t(), map()) :: {:ok, VerificationReceipt.t()} | {:error, Refusal.t()}
  def verify_staged(%Plan{} = plan, observed_hashes) when is_map(observed_hashes) do
    expected_paths = Map.keys(plan.file_hashes) |> MapSet.new()
    observed_paths = Map.keys(observed_hashes) |> MapSet.new()

    missing = MapSet.difference(expected_paths, observed_paths) |> MapSet.to_list() |> Enum.sort()
    extra = MapSet.difference(observed_paths, expected_paths) |> MapSet.to_list() |> Enum.sort()

    mismatched =
      MapSet.intersection(expected_paths, observed_paths)
      |> Enum.filter(fn path -> Map.fetch!(plan.file_hashes, path) != Map.fetch!(observed_hashes, path) end)
      |> Enum.sort()

    if missing == [] and extra == [] and mismatched == [] do
      observed_manifest_sha256 = Canonical.sha256(observed_hashes)

      receipt = %VerificationReceipt{
        status: :PARTIAL_ALIVE,
        standing: :staged_artifacts_verified,
        manifest_sha256: plan.manifest_sha256,
        observed_manifest_sha256: observed_manifest_sha256,
        verified?: true
      }

      {:ok, seal(receipt)}
    else
      {:error,
       Refusal.new(
         :REFUSED_MANUFACTURING_INCOMPLETE,
         :ggen_stage,
         "staged artifact graph does not exactly match the admitted manufacturing plan",
         %{missing: missing, extra: extra, mismatched: mismatched}
       )}
    end
  end

  defp seal(receipt) do
    hash = receipt |> Map.from_struct() |> Map.drop([:receipt_sha256]) |> Canonical.sha256()
    %{receipt | receipt_sha256: hash}
  end
end

defmodule AshR2RML.DfCM.IntegrityReceipt do
  @moduledoc "Receipt binding semantic-session identity, proof classes, and compiler receipt identity."

  defstruct [
    :status,
    :standing,
    :session_sha256,
    :compiler_receipt_sha256,
    :receipt_sha256,
    proofs: [],
    blocked: []
  ]

  @type t :: %__MODULE__{
          status: atom(),
          standing: atom(),
          session_sha256: String.t(),
          compiler_receipt_sha256: String.t(),
          receipt_sha256: String.t(),
          proofs: [atom()],
          blocked: [atom()]
        }
end

defmodule AshR2RML.DfCM.Compilation do
  @moduledoc "DfCM envelope around the existing ontology-first compiler result."
  defstruct [:compilation, :session_identity, :integrity_receipt, proof_classes: []]

  @type t :: %__MODULE__{
          compilation: AshR2RML.Compilation.t(),
          session_identity: AshR2RML.SemanticSessionIdentity.t(),
          integrity_receipt: AshR2RML.DfCM.IntegrityReceipt.t(),
          proof_classes: [atom()]
        }
end

defmodule AshR2RML.DfCM.Compiler do
  @moduledoc """
  DfCM admission wrapper around `AshR2RML.Compiler`.

  It adds bounded profile admission, exact semantic-session identity, typed proof
  standing, strict parity-witness binding, and deterministic integrity receipts
  without moving persistence, OBDA, or filesystem authority into the compiler.
  """

  alias AshR2RML.DfCM.{Compilation, IntegrityReceipt}
  alias AshR2RML.Integrity.Canonical
  alias AshR2RML.{Bounds, Proof, Refusal, SemanticDrift, SemanticSessionIdentity}

  @spec compile(map()) :: {:ok, Compilation.t()} | {:error, AshR2RML.Compilation.t() | Refusal.t()}
  def compile(profile) when is_map(profile) do
    with :ok <- Bounds.admit_profile(profile),
         {:ok, %AshR2RML.Compilation{} = compilation} <- AshR2RML.Compiler.compile(profile) do
      identity = session_identity(compilation)
      proofs = [:mapping_admitted, :projections_deterministic]
      {:ok, envelope(compilation, identity, proofs)}
    end
  end

  @doc "Bind exact PostgreSQL/OBDA environment identity and invalidate any prior external proof."
  @spec bind_verification_environment(Compilation.t(), map() | keyword()) :: Compilation.t()
  def bind_verification_environment(%Compilation{} = envelope, attrs) do
    identity = SemanticSessionIdentity.bind_environment(envelope.session_identity, attrs)

    proofs =
      envelope.proof_classes --
        [:relational_observed, :obda_query_observed, :subject_identity_verified, :result_parity_verified, :ontology_roundtrip_verified]

    receipt = envelope.compilation.receipt

    verified =
      Enum.reject(receipt.verified, fn
        {:parity_witness, _, _} -> true
        {:cutover_authority, _} -> true
        _ -> false
      end)

    reset_receipt = %{
      receipt
      | query_parity: :UNKNOWN,
        neo4j_postgres_parity: :UNKNOWN,
        cutover_authority: :UNAUTHORIZED,
        verified: verified,
        blocked:
          Enum.uniq(
            receipt.blocked ++
              [:sparql_sql_behavioral_parity, :neo4j_postgres_semantic_parity, :cutover_authority]
          )
    }

    refresh(%{
      envelope
      | session_identity: identity,
        proof_classes: proofs,
        compilation: %{envelope.compilation | receipt: reset_receipt}
    })
  end

  @spec receipt_reusable?(Compilation.t(), Compilation.t()) :: boolean()
  def receipt_reusable?(%Compilation{} = left, %Compilation{} = right) do
    SemanticSessionIdentity.matches?(left.session_identity, right.session_identity)
  end

  @spec admit_receipt_reuse(Compilation.t(), Compilation.t()) :: {:ok, :identical} | {:error, Refusal.t()}
  def admit_receipt_reuse(%Compilation{} = expected, %Compilation{} = observed) do
    SemanticSessionIdentity.admit_reuse(expected.session_identity, observed.session_identity)
  end

  @spec drift(Compilation.t(), Compilation.t()) :: SemanticDrift.t()
  def drift(%Compilation{} = old, %Compilation{} = new) do
    SemanticDrift.compare(old.compilation.ir, new.compilation.ir)
  end

  @spec incremental_plan(Compilation.t(), Compilation.t()) :: AshR2RML.DfCM.IncrementalPlan.t()
  def incremental_plan(%Compilation{} = old, %Compilation{} = new) do
    drift = SemanticDrift.compare(old.compilation.ir, new.compilation.ir)
    old_resources = Map.new(old.compilation.ir.resources, &{&1.class_iri, Canonical.sha256(&1)})
    new_resources = Map.new(new.compilation.ir.resources, &{&1.class_iri, Canonical.sha256(&1)})

    reusable =
      (Map.keys(old_resources) ++ Map.keys(new_resources))
      |> Enum.uniq()
      |> Enum.filter(fn class_iri ->
        Map.has_key?(old_resources, class_iri) and
          Map.get(old_resources, class_iri) == Map.get(new_resources, class_iri)
      end)
      |> Enum.sort()

    changed =
      (Map.keys(old_resources) ++ Map.keys(new_resources))
      |> Enum.uniq()
      |> Kernel.--(reusable)
      |> Enum.sort()

    exact? = SemanticSessionIdentity.matches?(old.session_identity, new.session_identity)

    %AshR2RML.DfCM.IncrementalPlan{
      mode: if(exact?, do: :reuse_exact_receipt, else: :recompile),
      old_session_sha256: old.session_identity.sha256,
      new_session_sha256: new.session_identity.sha256,
      drift_classification: drift.classification,
      reusable_resource_classes: reusable,
      changed_resource_classes: changed,
      blocked: if(exact?, do: [], else: [:fresh_projection_receipt, :fresh_external_parity])
    }
  end

  @spec attach_parity_witness(Compilation.t(), :sparql_sql | :neo4j_postgres, map()) :: Compilation.t()
  def attach_parity_witness(%Compilation{} = envelope, kind, witness)
      when kind in [:sparql_sql, :neo4j_postgres] and is_map(witness) do
    session_sha256 = get(witness, :session_sha256)
    verified? = get(witness, :verified?, false)
    observed? = get(witness, :observed?, false)
    left_observation_sha256 = get(witness, :left_observation_sha256)
    right_observation_sha256 = get(witness, :right_observation_sha256)
    witness_id = get(witness, :receipt_sha256)

    observed_receipts? =
      observed? and present_hash?(left_observation_sha256) and present_hash?(right_observation_sha256)

    if session_sha256 == envelope.session_identity.sha256 and verified? and observed_receipts? and
         is_binary(witness_id) and witness_id != "" do
      compiler_receipt =
        AshR2RML.Compiler.attach_parity_witness(envelope.compilation.receipt, kind, witness)

      proofs =
        envelope.proof_classes
        |> maybe_add(kind == :sparql_sql, :relational_observed)
        |> maybe_add(kind == :sparql_sql, :obda_query_observed)
        |> maybe_add(true, :result_parity_verified)
        |> maybe_add(get(witness, :subject_identity_verified?, false), :subject_identity_verified)

      refresh(%{envelope | compilation: %{envelope.compilation | receipt: compiler_receipt}, proof_classes: proofs})
    else
      refusal =
        Refusal.new(
          :REFUSED_UNPROVEN_EQUIVALENCE,
          kind,
          "parity witness is not bound to the exact semantic-session identity",
          %{
            expected_session_sha256: envelope.session_identity.sha256,
            observed_session_sha256: session_sha256,
            verified?: verified?,
            observed?: observed?,
            observation_receipts_present?: observed_receipts?,
            receipt_present?: is_binary(witness_id) and witness_id != ""
          }
        )

      compiler_receipt = %{envelope.compilation.receipt | refusals: [refusal | envelope.compilation.receipt.refusals]}
      refresh(%{envelope | compilation: %{envelope.compilation | receipt: compiler_receipt}})
    end
  end

  @spec authorize_cutover(Compilation.t(), map()) :: Compilation.t()
  def authorize_cutover(%Compilation{} = envelope, authority) when is_map(authority) do
    compiler_receipt = AshR2RML.Compiler.authorize_cutover(envelope.compilation.receipt, authority)
    refresh(%{envelope | compilation: %{envelope.compilation | receipt: compiler_receipt}})
  end

  @spec cutover_ready?(Compilation.t()) :: boolean()
  def cutover_ready?(%Compilation{} = envelope) do
    AshR2RML.Compiler.cutover_ready?(envelope.compilation.receipt) and
      Proof.achieved?(envelope.proof_classes, :subject_parity_alive)
  end

  defp session_identity(compilation) do
    receipt = compilation.receipt

    SemanticSessionIdentity.new(%{
      ontology_hash: receipt.ontology_hash,
      profile_hash: receipt.profile_hash,
      shacl_hash: receipt.shacl_input_hash,
      ir_sha256: receipt.ir_sha256,
      mapping_sha256: receipt.mapping_sha256,
      metadata: %{
        projection_hashes: %{
          ash: receipt.ash_sha256,
          ecto: receipt.ecto_sha256,
          postgres: receipt.postgres_sha256,
          r2rml: receipt.r2rml_sha256,
          shacl: receipt.shacl_sha256
        }
      }
    })
  end

  defp envelope(compilation, identity, proofs) do
    %Compilation{
      compilation: compilation,
      session_identity: identity,
      proof_classes: proofs
    }
    |> refresh()
  end

  defp refresh(%Compilation{} = envelope) do
    compiler_receipt_sha256 = Canonical.sha256(envelope.compilation.receipt)
    standing = Proof.highest(envelope.proof_classes)

    integrity = %IntegrityReceipt{
      status: envelope.compilation.status,
      standing: standing,
      session_sha256: envelope.session_identity.sha256,
      compiler_receipt_sha256: compiler_receipt_sha256,
      proofs: Enum.sort(envelope.proof_classes),
      blocked: envelope.compilation.receipt.blocked
    }

    integrity_hash = integrity |> Map.from_struct() |> Map.drop([:receipt_sha256]) |> Canonical.sha256()
    %{envelope | integrity_receipt: %{integrity | receipt_sha256: integrity_hash}}
  end

  defp present_hash?(value), do: is_binary(value) and value != ""

  defp maybe_add(proofs, true, proof), do: Proof.add(proofs, proof)
  defp maybe_add(proofs, false, _proof), do: proofs

  defp get(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end
end

defmodule AshR2RML.LivebookSpec do
  @moduledoc """
  Executes explicitly marked Elixir test cells from versioned `.livemd` files.

  This is intentionally a small CI contract, not a replacement Livebook runtime:
  only fenced cells marked `elixir ash_r2rml_test` are executed, in document
  order, with bindings carried forward. Smart cells and branching sections are
  outside this verifier and therefore cannot silently acquire execution authority.
  """

  alias AshR2RML.Refusal

  @cell ~r/```elixir\s+ash_r2rml_test[^\n]*\n(.*?)\n```/ms

  @spec run(String.t()) :: {:ok, map()} | {:error, Refusal.t()}
  def run(path) when is_binary(path) do
    with {:ok, source} <- File.read(path),
         cells when cells != [] <- extract_cells(source) do
      evaluate_cells(path, cells)
    else
      {:error, reason} ->
        {:error,
         Refusal.new(
           :REFUSED_LIVEBOOK_SPEC,
           path,
           "failed to read executable Livebook specification",
           %{error_class: classify_file_error(reason)}
         )}

      [] ->
        {:error,
         Refusal.new(
           :REFUSED_LIVEBOOK_SPEC,
           path,
           "Livebook contains no explicitly admitted ash_r2rml_test cells",
           %{}
         )}
    end
  end

  defp extract_cells(source) do
    Regex.scan(@cell, source, capture: :all_but_first)
    |> Enum.map(fn [code] -> code end)
  end

  defp evaluate_cells(path, cells) do
    cells
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, {[], nil}}, fn {code, index}, {:ok, {binding, _last}} ->
      try do
        {value, next_binding} = Code.eval_string(code, binding, file: "#{path}:cell#{index}")
        {:cont, {:ok, {next_binding, value}}}
      rescue
        exception ->
          {:halt,
           {:error,
            Refusal.new(
              :REFUSED_LIVEBOOK_SPEC,
              path,
              "executable Livebook specification cell failed",
              %{cell: index, exception_class: inspect(exception.__struct__)}
            )}}
      catch
        kind, _reason ->
          {:halt,
           {:error,
            Refusal.new(
              :REFUSED_LIVEBOOK_SPEC,
              path,
              "executable Livebook specification cell exited abnormally",
              %{cell: index, exit_class: kind}
            )}}
      end
    end)
    |> case do
      {:ok, {_binding, last}} -> {:ok, %{cells: length(cells), final: last}}
      error -> error
    end
  end

  defp classify_file_error(reason) when reason in [:enoent, :eacces, :eisdir], do: reason
  defp classify_file_error(_), do: :file_error
end