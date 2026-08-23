# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.SemanticType do
  @moduledoc """
  Canonical admitted value-space projection.

  A semantic type is deliberately independent of Ash source, PostgreSQL DDL,
  R2RML syntax, JSON-LD syntax, Igniter patches, and ggen templates. Those are
  projections of this object.
  """

  @semantic_kinds [:literal, :iri, :concept, :value_object, :resource]

  @enforce_keys [:name, :semantic_kind, :ash_type]
  defstruct [
    :id,
    :name,
    :provider,
    :source_iri,
    :semantic_kind,
    :ash_type,
    :datatype_iri,
    :class_iri,
    :concept_scheme_iri,
    :storage_type,
    :postgres_type,
    :selected_representation,
    constraints: [],
    shacl_constraints: [],
    representation_candidates: [],
    provenance: %{}
  ]

  @type representation ::
          :builtin
          | :new_type
          | :custom_type
          | :registry
          | :composite
          | :embedded
          | :jsonb
          | :resource

  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: atom(),
          provider: atom() | nil,
          source_iri: String.t() | nil,
          semantic_kind: AshR2RML.Type.semantic_kind(),
          ash_type: atom() | module(),
          datatype_iri: String.t() | nil,
          class_iri: String.t() | nil,
          concept_scheme_iri: String.t() | nil,
          storage_type: atom() | term() | nil,
          postgres_type: String.t() | nil,
          constraints: keyword() | map(),
          shacl_constraints: keyword() | map(),
          representation_candidates: [representation()],
          selected_representation: representation() | nil,
          provenance: map()
        }

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, AshR2RML.Refusal.t()}
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) do
    semantic_kind = get(attrs, :semantic_kind)
    ash_type = get(attrs, :ash_type)
    name = get(attrs, :name)

    cond do
      not is_atom(name) ->
        refusal(:REFUSED_SEMANTIC_TYPE_INVALID, name, "semantic type name must be an atom")

      semantic_kind not in @semantic_kinds ->
        refusal(
          :REFUSED_SEMANTIC_TYPE_INVALID,
          name,
          "unsupported semantic kind",
          %{semantic_kind: semantic_kind}
        )

      not (is_atom(ash_type) or is_tuple(ash_type)) ->
        refusal(
          :REFUSED_SEMANTIC_TYPE_INVALID,
          name,
          "semantic type requires an Ash type projection",
          %{ash_type: ash_type}
        )

      true ->
        type =
          struct!(__MODULE__, %{
            name: name,
            provider: get(attrs, :provider),
            source_iri: get(attrs, :source_iri),
            semantic_kind: semantic_kind,
            ash_type: ash_type,
            datatype_iri: get(attrs, :datatype_iri),
            class_iri: get(attrs, :class_iri),
            concept_scheme_iri: get(attrs, :concept_scheme_iri),
            storage_type: get(attrs, :storage_type),
            postgres_type: get(attrs, :postgres_type),
            selected_representation: get(attrs, :selected_representation),
            constraints: get(attrs, :constraints, []),
            shacl_constraints: get(attrs, :shacl_constraints, []),
            representation_candidates: get(attrs, :representation_candidates, []),
            provenance: get(attrs, :provenance, %{})
          })

        AshR2RML.SemanticType.DfCM.select(type)
    end
  end

  @spec canonical(t()) :: map()
  def canonical(%__MODULE__{} = type) do
    %{
      name: type.name,
      provider: type.provider,
      source_iri: type.source_iri,
      semantic_kind: type.semantic_kind,
      ash_type: canonical_term(type.ash_type),
      datatype_iri: type.datatype_iri,
      class_iri: type.class_iri,
      concept_scheme_iri: type.concept_scheme_iri,
      storage_type: canonical_term(type.storage_type),
      postgres_type: type.postgres_type,
      constraints: canonical_term(type.constraints),
      shacl_constraints: canonical_term(type.shacl_constraints),
      representation_candidates: Enum.sort(type.representation_candidates),
      selected_representation: type.selected_representation,
      provenance: canonical_term(type.provenance)
    }
  end

  @spec hash(t()) :: String.t()
  def hash(%__MODULE__{} = type) do
    type
    |> canonical()
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @spec absolute_iri?(term()) :: boolean()
  def absolute_iri?(value) when is_binary(value) do
    case URI.parse(value) do
      %URI{scheme: scheme} when is_binary(scheme) and scheme != "" -> true
      _ -> false
    end
  end

  def absolute_iri?(_), do: false

  defp refusal(code, subject, detail, evidence \\ %{}) do
    {:error, AshR2RML.Refusal.new(code, subject, detail, evidence)}
  end

  defp canonical_term(value) when is_map(value) do
    value
    |> Enum.map(fn {key, item} -> {to_string(canonical_term(key)), canonical_term(item)} end)
    |> Map.new()
  end

  defp canonical_term(value) when is_list(value) do
    if Keyword.keyword?(value) do
      value
      |> Enum.map(fn {k, v} -> {to_string(k), canonical_term(v)} end)
      |> Map.new()
    else
      Enum.map(value, &canonical_term/1)
    end
  end

  defp canonical_term(value) when is_tuple(value), do: value |> Tuple.to_list() |> Enum.map(&canonical_term/1)
  defp canonical_term(value) when is_atom(value), do: Atom.to_string(value)
  defp canonical_term(value), do: value

  defp get(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end
end

defmodule AshR2RML.SemanticType.Plan do
  @moduledoc "Content-addressed SELECT/CONSTRUCT plan over admitted semantic types."

  defstruct [:id, types: [], providers: [], refusals: [], status: :PARTIAL_ALIVE]

  @type t :: %__MODULE__{
          id: String.t(),
          types: [AshR2RML.SemanticType.t()],
          providers: [atom()],
          refusals: [AshR2RML.Refusal.t()],
          status: :PARTIAL_ALIVE | :ALIVE
        }
end

defmodule AshR2RML.SemanticType.Diff do
  @moduledoc "Observed-vs-admitted semantic type drift without implicit repair."

  defstruct [:status, changes: [], expected_id: nil, observed_id: nil]

  @type status ::
          :ALIGNED
          | :ONTOLOGY_AHEAD
          | :ASH_AHEAD
          | :AMBIGUOUS
          | :LOSSY
          | :REFUSED

  @type t :: %__MODULE__{
          status: status(),
          changes: [map()],
          expected_id: String.t() | nil,
          observed_id: String.t() | nil
        }
end

defmodule AshR2RML.SemanticType.Provider do
  @moduledoc """
  Extension point for public ontology/application-profile value spaces.

  Providers interpret public terms. They do not write files, apply migrations,
  or grant execution authority.
  """

  @callback id() :: atom()
  @callback prefixes() :: map()
  @callback resolve(String.t(), keyword()) ::
              {:ok, AshR2RML.SemanticType.t()} | :unknown | {:error, term()}
  @callback catalogue() :: [String.t()]
end

defmodule AshR2RML.SemanticType.DfCM do
  @moduledoc """
  DfCM representation calculus for semantic values.

  Candidate preservation is separate from irreversible selection.
  """

  alias AshR2RML.{Refusal, SemanticType}

  @spec candidates(SemanticType.t()) :: [SemanticType.representation()]
  def candidates(%SemanticType{representation_candidates: [_ | _] = candidates}),
    do: Enum.uniq(candidates)

  def candidates(%SemanticType{semantic_kind: :literal}) do
    [:builtin, :new_type, :custom_type, :registry]
  end

  def candidates(%SemanticType{semantic_kind: :iri}) do
    [:new_type, :custom_type, :registry]
  end

  def candidates(%SemanticType{semantic_kind: :concept}) do
    [:custom_type, :registry, :resource]
  end

  def candidates(%SemanticType{semantic_kind: :value_object}) do
    [:composite, :embedded, :jsonb, :resource]
  end

  def candidates(%SemanticType{semantic_kind: :resource}), do: [:resource]

  @spec select(SemanticType.t()) :: {:ok, SemanticType.t()} | {:error, Refusal.t()}
  def select(%SemanticType{} = type) do
    candidates = candidates(type)
    type = %{type | representation_candidates: candidates}

    case type.selected_representation do
      nil ->
        {:ok, %{type | id: SemanticType.hash(type)}}

      selected ->
        if selected in candidates do
          selected_type = %{type | selected_representation: selected}
          {:ok, %{selected_type | id: SemanticType.hash(selected_type)}}
        else
          {:error,
           Refusal.new(
             :REFUSED_SEMANTIC_TYPE_REPRESENTATION,
             type.name,
             "selected representation is not in the admitted DfCM candidate set",
             %{selected: selected, candidates: candidates}
           )}
        end
    end
  end
end
