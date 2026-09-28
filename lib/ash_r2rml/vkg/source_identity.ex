defmodule AshR2RML.VKG.SourceIdentity do
  @moduledoc """
  Exact identity of one virtual knowledge graph source descriptor.

  A source identity is a configuration identity, not a claim that the underlying
  database contents are immutable. The digest binds the admitted source URI,
  graph URI, subject template, and optional version so downstream plans can
  refuse descriptor drift before any query is executed.
  """

  alias AshR2RML.Refusal

  @enforce_keys [:id, :uri, :graph, :subject_template, :sha256]
  defstruct [:id, :uri, :graph, :subject_template, :version, :sha256]

  @type t :: %__MODULE__{
          id: String.t(),
          uri: String.t(),
          graph: String.t(),
          subject_template: String.t(),
          version: String.t() | nil,
          sha256: String.t()
        }

  @spec new(map()) :: {:ok, t()} | {:error, Refusal.t()}
  def new(attrs) when is_map(attrs) do
    id = fetch(attrs, :id)
    uri = fetch(attrs, :uri) || fetch(attrs, :source)
    graph = fetch(attrs, :graph)
    subject_template = fetch(attrs, :subject_template)
    version = fetch(attrs, :version)

    cond do
      not (is_nil(version) or non_empty?(version)) ->
        refusal(:version, "source identity version must be nil or a non-empty string", attrs)

      not non_empty?(id) ->
        refusal(:id, "source identity requires a non-empty id", attrs)

      not absolute_identity?(uri) ->
        refusal(:uri, "source identity requires an absolute URI/URN", attrs)

      not absolute_identity?(graph) ->
        refusal(:graph, "source identity requires an absolute graph URI/URN", attrs)

      not non_empty?(subject_template) ->
        refusal(:subject_template, "source identity requires a subject template", attrs)

      true ->
        canonical = {id, uri, graph, subject_template, version}

        {:ok,
         %__MODULE__{
           id: id,
           uri: uri,
           graph: graph,
           subject_template: subject_template,
           version: version,
           sha256: sha256(canonical)
         }}
    end
  end

  def new(other), do: refusal(:shape, "source identity must be a map", %{value: inspect(other)})

  @spec same?(t(), t()) :: boolean()
  def same?(%__MODULE__{} = left, %__MODULE__{} = right) do
    left.id == right.id and left.sha256 == right.sha256
  end

  @spec verify(t(), String.t()) :: :ok | {:error, Refusal.t()}
  def verify(%__MODULE__{} = identity, expected_sha256) do
    if identity.sha256 == expected_sha256 do
      :ok
    else
      {:error,
       Refusal.new(
         :REFUSED_VKG_SOURCE_DRIFT,
         identity.id,
         "source descriptor identity does not match the admitted digest",
         %{expected: expected_sha256, observed: identity.sha256}
       )}
    end
  end

  @spec fingerprint(t()) :: String.t()
  def fingerprint(%__MODULE__{sha256: sha256}), do: sha256

  defp refusal(subject, detail, evidence) do
    {:error, Refusal.new(:REFUSED_VKG_SOURCE_IDENTITY, subject, detail, evidence)}
  end

  defp non_empty?(value), do: is_binary(value) and String.trim(value) != ""

  defp absolute_identity?(value) when is_binary(value) do
    String.match?(value, ~r/\A(urn:[A-Za-z0-9][A-Za-z0-9-]*:\S+|https?:\/\/[^\s\/?#]+\S*)\z/)
  end

  defp absolute_identity?(_), do: false

  defp fetch(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp sha256(term) do
    term
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
