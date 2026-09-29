defmodule AshR2RML.VKG.SA2AEvidence do
  @moduledoc """
  Portable, authority-free SA2A semantic evidence projected from an exact VKG source.

  The envelope is deliberately inert: it carries evidence identity, provenance and
  replay material, but never authorization or a DO capability. Its canonical digest
  is computed with the existing cross-runtime VKG canonical JSON serializer.
  """

  alias AshR2RML.Refusal
  alias AshR2RML.VKG.{Receipt, Serializer, SourceIdentity}

  @schema "sa2a.semantic-evidence-envelope.v1"
  @contract_version "v26.9.29"
  @canonicalization "RDFC-1.0"
  @authority "NONE"
  @consequence "EVIDENCE_ONLY"
  @graphlaw_contract_commit "4e4873ca377d50af5268e8736be4afe6badeb862"

  @required ~w(schema contractVersion canonicalization authority consequence subject source graphDigest replayIdentity provenance envelopeDigest)

  @spec from_source(SourceIdentity.t(), map()) :: {:ok, map()} | {:error, Refusal.t()}
  def from_source(source, attrs \\ %{})

  def from_source(%SourceIdentity{} = source, attrs) when is_map(attrs) do
    subject = fetch(attrs, :subject) || source.id

    with :ok <- non_empty(subject, :subject),
         {:ok, graph_digest} <- digest(fetch(attrs, :graph_digest) || source.sha256, :graph_digest),
         {:ok, replay_identity} <- replay_identity(attrs, source),
         {:ok, receipt_digest} <- receipt_digest(fetch(attrs, :receipt)) do
      envelope =
        %{
          "schema" => @schema,
          "contractVersion" => @contract_version,
          "canonicalization" => @canonicalization,
          "authority" => @authority,
          "consequence" => @consequence,
          "subject" => subject,
          "source" => %{
            "id" => source.id,
            "uri" => source.uri,
            "graph" => source.graph,
            "subjectTemplate" => source.subject_template,
            "version" => source.version,
            "digest" => "sha256:" <> source.sha256
          },
          "graphDigest" => graph_digest,
          "replayIdentity" => replay_identity,
          "receiptDigest" => receipt_digest,
          "provenance" => %{
            "producer" => "ash_r2rml",
            "producerVersion" => app_version(),
            "graphlawContractCommit" => @graphlaw_contract_commit,
            "sourceIdentityDigest" => "sha256:" <> source.sha256
          }
        }
        |> put_optional_provenance(fetch(attrs, :provenance))

      {:ok, seal(envelope)}
    end
  end

  def from_source(other, _attrs),
    do: refusal(:source, "SA2A evidence requires an admitted VKG SourceIdentity", %{got: inspect(other)})

  @spec verify(map()) :: :ok | {:error, Refusal.t()}
  def verify(envelope) when is_map(envelope) do
    missing = Enum.reject(@required, &Map.has_key?(envelope, &1))

    cond do
      missing != [] ->
        refusal(:envelope, "SA2A evidence envelope is missing required fields", %{missing: missing})

      envelope["schema"] != @schema ->
        refusal(:schema, "unsupported SA2A evidence schema", %{observed: envelope["schema"]})

      envelope["contractVersion"] != @contract_version ->
        refusal(:contract_version, "unsupported GraphLaw evidence contract version", %{
          observed: envelope["contractVersion"]
        })

      envelope["canonicalization"] != @canonicalization ->
        refusal(:canonicalization, "semantic evidence must declare RDFC-1.0 canonicalization", %{
          observed: envelope["canonicalization"]
        })

      envelope["authority"] != @authority ->
        refusal(:authority, "semantic evidence cannot acquire consequential authority", %{
          observed: envelope["authority"]
        })

      envelope["consequence"] != @consequence ->
        refusal(:consequence, "semantic evidence is evidence-only", %{observed: envelope["consequence"]})

      not valid_source?(envelope["source"]) ->
        refusal(:source, "semantic evidence source identity is incomplete or non-exact", %{})

      not sha256?(envelope["graphDigest"]) ->
        refusal(:graph_digest, "semantic evidence graph digest must be sha256:<64 hex>", %{})

      not non_empty_value?(envelope["replayIdentity"]) ->
        refusal(:replay_identity, "semantic evidence requires a replay identity", %{})

      envelope["envelopeDigest"] != "sha256:" <> Serializer.digest(Map.delete(envelope, "envelopeDigest")) ->
        refusal(:envelope_digest, "semantic evidence envelope digest does not replay", %{
          observed: envelope["envelopeDigest"]
        })

      true ->
        :ok
    end
  end

  def verify(other),
    do: refusal(:envelope, "SA2A evidence envelope must be a map", %{got: inspect(other)})

  @spec encode!(map()) :: String.t()
  def encode!(envelope) do
    case verify(envelope) do
      :ok -> Serializer.canonical_json(envelope)
      {:error, refusal} -> raise ArgumentError, "invalid SA2A evidence envelope: #{inspect(refusal)}"
    end
  end

  defp seal(envelope), do: Map.put(envelope, "envelopeDigest", "sha256:" <> Serializer.digest(envelope))

  defp put_optional_provenance(envelope, nil), do: envelope

  defp put_optional_provenance(envelope, extra) when is_map(extra) do
    update_in(envelope, ["provenance"], &Map.merge(&1, stringify(extra)))
  end

  defp put_optional_provenance(envelope, _), do: envelope

  defp replay_identity(attrs, source) do
    case fetch(attrs, :replay_identity) do
      nil -> {:ok, "vkg-source:" <> source.sha256}
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> refusal(:replay_identity, "replay identity must be a non-empty string", %{})
    end
  end

  defp receipt_digest(nil), do: {:ok, nil}
  defp receipt_digest(%Receipt{sha256: digest}), do: digest(digest, :receipt)
  defp receipt_digest(value) when is_binary(value), do: digest(value, :receipt)
  defp receipt_digest(other), do: refusal(:receipt, "receipt must be a VKG receipt or digest", %{got: inspect(other)})

  defp digest("sha256:" <> _hex = digest, subject) do
    if Regex.match?(~r/\Asha256:[0-9a-f]{64}\z/, digest),
      do: {:ok, digest},
      else: refusal(subject, "digest must be sha256:<64 lowercase hex>", %{observed: digest})
  end

  defp digest(hex, subject) when is_binary(hex) do
    if Regex.match?(~r/\A[0-9a-f]{64}\z/, hex),
      do: {:ok, "sha256:" <> hex},
      else: refusal(subject, "digest must be 64 lowercase hex characters", %{observed: hex})
  end

  defp digest(value, subject),
    do: refusal(subject, "digest must be a string", %{observed: inspect(value)})

  defp valid_source?(%{
         "id" => id,
         "uri" => uri,
         "graph" => graph,
         "subjectTemplate" => template,
         "digest" => digest
       }) do
    Enum.all?([id, uri, graph, template], &non_empty_value?/1) and sha256?(digest)
  end

  defp valid_source?(_), do: false

  defp sha256?(value), do: is_binary(value) and Regex.match?(~r/\Asha256:[0-9a-f]{64}\z/, value)
  defp non_empty_value?(value), do: is_binary(value) and String.trim(value) != ""

  defp non_empty(value, _subject) when is_binary(value) and value != "", do: :ok
  defp non_empty(_value, subject), do: refusal(subject, "value must be a non-empty string", %{})

  defp fetch(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp stringify(map), do: Map.new(map, fn {key, value} -> {to_string(key), value} end)

  defp app_version do
    case Application.spec(:ash_r2rml, :vsn) do
      nil -> "unknown"
      vsn -> to_string(vsn)
    end
  end

  defp refusal(subject, detail, evidence),
    do: {:error, Refusal.new(:REFUSED_VKG_SOURCE_IDENTITY, subject, detail, evidence)}
end
