defmodule AshR2RML.Gall.RuntimeFeedback do
  @moduledoc """
  GALL-009 runtime-feedback admission.

  Runtime/telemetry evidence is mapped into a candidate RDF delta first.
  Candidate triples never mutate a canonical graph. Only admit/3 can produce
  an admitted delta and a new semantic subject digest, after public-vocabulary
  and caller-supplied law/shape gates have passed.
  """

  @enforce_keys [:source_evidence_digest, :mapping_digest, :subject_iri, :triples, :candidate_digest]
  defstruct [
    :source_evidence_digest,
    :mapping_digest,
    :subject_iri,
    :triples,
    :candidate_digest,
    standing: :candidate
  ]

  defmodule AdmittedDelta do
    @moduledoc "A candidate delta that passed all GALL-009 admission gates."
    @enforce_keys [
      :source_evidence_digest,
      :mapping_digest,
      :subject_iri,
      :triples,
      :candidate_digest,
      :predecessor_graph_digest,
      :new_graph_digest,
      :admission_receipt_digest
    ]
    defstruct [
      :source_evidence_digest,
      :mapping_digest,
      :subject_iri,
      :triples,
      :candidate_digest,
      :predecessor_graph_digest,
      :new_graph_digest,
      :admission_receipt_digest,
      standing: :admitted
    ]
  end

  @type mapping_rule :: %{
          required(:source_key) => String.t() | atom(),
          required(:predicate) => String.t(),
          optional(:object) => :literal | :iri
        }

  @doc """
  Map an observed evidence map into deterministic candidate RDF statements.

  A mapping rule names one source key and one predicate. No source key means
  no triple; this is an observation mapper, not an inference engine.
  """
  def candidate(observation, opts)
      when is_map(observation) and is_list(opts) do
    source_evidence_digest = Keyword.fetch!(opts, :source_evidence_digest)
    subject_iri = Keyword.fetch!(opts, :subject_iri)
    mapping = Keyword.fetch!(opts, :mapping)

    with :ok <- digest(source_evidence_digest, :source_evidence_digest),
         :ok <- absolute_iri(subject_iri, :subject_iri),
         {:ok, triples} <- map_rules(observation, subject_iri, mapping) do
      mapping_digest = hash(mapping)
      payload = %{
        source_evidence_digest: source_evidence_digest,
        mapping_digest: mapping_digest,
        subject_iri: subject_iri,
        triples: triples
      }

      {:ok,
       %__MODULE__{
         source_evidence_digest: source_evidence_digest,
         mapping_digest: mapping_digest,
         subject_iri: subject_iri,
         triples: triples,
         candidate_digest: hash(payload)
       }}
    end
  end

  @doc """
  Admit a candidate against a predecessor graph identity.

  public_namespaces is an explicit allow-list. gates are pure functions
  taking the candidate and returning :ok or {:error, reason}. Admission
  does not write a graph; it manufactures the exact new graph identity that
  a canonical graph store may apply transactionally.
  """
  def admit(%__MODULE__{standing: :candidate} = candidate, predecessor_graph_digest, opts)
      when is_list(opts) do
    public_namespaces = Keyword.get(opts, :public_namespaces, [])
    gates = Keyword.get(opts, :gates, [])

    with :ok <- digest(predecessor_graph_digest, :predecessor_graph_digest),
         :ok <- public_vocabulary(candidate, public_namespaces),
         :ok <- run_gates(candidate, gates) do
      new_graph_digest =
        hash(%{
          predecessor_graph_digest: predecessor_graph_digest,
          candidate_digest: candidate.candidate_digest,
          triples: candidate.triples
        })

      receipt =
        hash(%{
          source_evidence_digest: candidate.source_evidence_digest,
          mapping_digest: candidate.mapping_digest,
          candidate_digest: candidate.candidate_digest,
          predecessor_graph_digest: predecessor_graph_digest,
          new_graph_digest: new_graph_digest,
          gates:
            Enum.with_index(gates, 1)
            |> Enum.map(fn {_gate, index} -> "gate-#{index}:PASS" end)
        })

      {:ok,
       %AdmittedDelta{
         source_evidence_digest: candidate.source_evidence_digest,
         mapping_digest: candidate.mapping_digest,
         subject_iri: candidate.subject_iri,
         triples: candidate.triples,
         candidate_digest: candidate.candidate_digest,
         predecessor_graph_digest: predecessor_graph_digest,
         new_graph_digest: new_graph_digest,
         admission_receipt_digest: receipt
       }}
    else
      {:error, reason} -> {:error, {:refused_runtime_feedback, reason}}
    end
  end

  @doc """
  Projects an admitted delta into a content-addressed GALL-009 evidence receipt.

  The producer SHA is caller-bound exact-head identity; this function does not
  read git state, write the canonical graph, or promote repository standing.
  """
  def receipt(%AdmittedDelta{} = admitted, producer_sha, opts \\ []) do
    with :ok <- git_sha(producer_sha) do
      payload = %{
        "schema" => "gall.runtime-feedback-receipt/1",
        "checkpoint" => "GALL-009",
        "producer_sha" => producer_sha,
        "subject_iri" => admitted.subject_iri,
        "source_evidence_digest" => admitted.source_evidence_digest,
        "mapping_digest" => admitted.mapping_digest,
        "candidate_digest" => admitted.candidate_digest,
        "predecessor_graph_digest" => admitted.predecessor_graph_digest,
        "new_graph_digest" => admitted.new_graph_digest,
        "admission_receipt_digest" => admitted.admission_receipt_digest,
        "court" => Keyword.get(opts, :court, "runtime-feedback-admission"),
        "falsifiers" => [
          "source-evidence-bound",
          "mapping-identity-bound",
          "public-vocabulary-only",
          "admission-gates-pass"
        ],
        "result" => "ADMITTED_DELTA",
        "authority" => "NONE",
        "evidence_ceiling" => "semantic admission/construct only; no canonical write or DO"
      }

      {:ok, Map.put(payload, "receipt_digest", hash(payload))}
    end
  end

  defp git_sha(value) when is_binary(value) do
    if byte_size(value) == 40 and value =~ ~r/^[0-9a-f]+$/ do
      :ok
    else
      {:error, {:producer_sha, :invalid_git_sha}}
    end
  end

  defp git_sha(_), do: {:error, {:producer_sha, :invalid_git_sha}}

  defp map_rules(observation, subject_iri, mapping) when is_list(mapping) do
    mapping
    |> Enum.reduce_while({:ok, []}, fn rule, {:ok, acc} ->
      key = Map.fetch!(rule, :source_key)
      predicate = Map.fetch!(rule, :predicate)
      object_kind = Map.get(rule, :object, :literal)

      with :ok <- absolute_iri(predicate, :predicate) do
        case fetch_observation(observation, key) do
          :missing ->
            {:cont, {:ok, acc}}

          {:ok, value} ->
            object =
              case object_kind do
                :literal -> {:literal, value}
                :iri when is_binary(value) -> {:iri, value}
                other -> {:invalid_object_kind, other}
              end

            case object do
              {:iri, iri} ->
                case absolute_iri(iri, :object_iri) do
                  :ok -> {:cont, {:ok, [{subject_iri, predicate, object} | acc]}}
                  {:error, reason} -> {:halt, {:error, reason}}
                end

              {:literal, _} ->
                {:cont, {:ok, [{subject_iri, predicate, object} | acc]}}

              {:invalid_object_kind, other} ->
                {:halt, {:error, {:object_kind, other}}}
            end
        end
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, triples} ->
        triples =
          triples
          |> Enum.reverse()
          |> Enum.sort_by(&canonical/1)

        if triples == [] do
          {:error, :no_candidate_triples}
        else
          {:ok, triples}
        end

      error ->
        error
    end
  end

  defp fetch_observation(map, key) do
    candidates = Enum.uniq([key, to_string(key)])

    case Enum.find_value(candidates, fn candidate ->
           case Map.fetch(map, candidate) do
             {:ok, value} -> {:found, value}
             :error -> nil
           end
         end) do
      {:found, value} -> {:ok, value}
      nil -> :missing
    end
  end

  defp public_vocabulary(candidate, namespaces) do
    predicates = Enum.map(candidate.triples, &elem(&1, 1))

    case Enum.find(predicates, fn predicate ->
           not Enum.any?(namespaces, &String.starts_with?(predicate, &1))
         end) do
      nil -> :ok
      private -> {:error, {:nonpublic_vocabulary, private}}
    end
  end

  defp run_gates(candidate, gates) do
    Enum.reduce_while(gates, :ok, fn gate, :ok ->
      case gate.(candidate) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:gate_refused, reason}}}
        other -> {:halt, {:error, {:invalid_gate_result, other}}}
      end
    end)
  end

  defp absolute_iri(value, field) when is_binary(value) do
    if String.starts_with?(value, ["http://", "https://", "urn:"]) do
      :ok
    else
      {:error, {field, :not_absolute_iri}}
    end
  end

  defp absolute_iri(_value, field), do: {:error, {field, :not_iri}}

  defp digest("sha256:" <> hex, _field) when byte_size(hex) == 64 do
    if hex =~ ~r/^[0-9a-f]+$/, do: :ok, else: {:error, :invalid_sha256_hex}
  end

  defp digest(_value, field), do: {:error, {field, :invalid_digest}}

  defp hash(value) do
    value
    |> canonical()
    |> :crypto.hash(:sha256)
    |> Base.encode16(case: :lower)
    |> then(&("sha256:" <> &1))
  end

  defp canonical(value) when is_map(value) do
    value
    |> Enum.map(fn {key, item} -> {to_string(key), canonical(item)} end)
    |> Enum.sort_by(&elem(&1, 0))
    |> inspect(limit: :infinity, printable_limit: :infinity)
  end

  defp canonical(value) when is_list(value), do: Enum.map(value, &canonical/1) |> inspect()
  defp canonical(value) when is_tuple(value), do: value |> Tuple.to_list() |> canonical()
  defp canonical(value), do: inspect(value, limit: :infinity, printable_limit: :infinity)
end
