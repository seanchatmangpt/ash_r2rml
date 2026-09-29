defmodule AshR2RML.VKG.Serializer do
  @moduledoc """
  Canonical JSON encoding, stable JSON projections, and digests for VKG values.

  `canonical_json/1` is the single identity encoding for VKG receipts, results
  and provenance. It is independent of the BEAM external term format:

    * object keys are stringified and emitted in sorted order;
    * `nil`, `true` and `false` stay JSON `null`/`true`/`false`;
    * every other atom encodes as `{"$atom": name}`, tuples as `{"$tuple": [...]}`,
      dates/times/datetimes as `{"$date": iso}` (`$time`, `$naive_datetime`,
      `$datetime`) and decimals as `{"$decimal": string}`; other structs as an
      object carrying `"$struct"`;
    * non-UTF-8 binaries encode as `{"$binary": base64}`;
    * user maps with any `"$"`-prefixed key are wrapped as `{"$map": {...}}`, so
      the reserved tags above can never be spelled by data;
    * maps whose keys collide after stringification (`:a` and `"a"`) or that use
      keys other than strings/atoms encode as `{"$pairs": [[key, value], ...]}` so no
      member is ever dropped.

  The value encoding is injective: an atom, a date, a decimal, a tuple, a list, a
  map and a string never share an encoding, so a value cannot change type while
  keeping its digest. The one deliberate identification is the *key namespace*:
  an atom map key is equivalent to the string of its name (rows always carry
  string keys once sealed).

  `Result` still projects rows to JSON-native values before sealing, so sealed
  results survive a JSON round trip; that projection is not what protects the
  digest (the tagged encoding is), and `Result.verify/1` refuses rows that are
  not already in the projected form. `decode_value/1` reverses the tags for
  values that were not projected.

  Because the encoding is plain JSON, a JSON round trip of a JSON-native value
  reproduces the same digest, so a non-BEAM verifier can recompute it.
  """

  alias AshR2RML.Refusal
  alias AshR2RML.VKG.{Receipt, Result, Session}

  @digest_domain "ashr2rml.vkg.canonical.v1\n"

  @doc "Canonical JSON binary for any term (total function)."
  @spec canonical_json(term()) :: binary()
  def canonical_json(term), do: term |> encode() |> IO.iodata_to_binary()

  @doc "Full lowercase sha256 over the versioned canonical JSON of `term`."
  @spec digest(term()) :: String.t()
  def digest(term) do
    :crypto.hash(:sha256, [@digest_domain, canonical_json(term)])
    |> Base.encode16(case: :lower)
  end

  @doc "Deterministic string form of a map key."
  @spec key_string(term()) :: String.t()
  def key_string(key) when is_binary(key), do: key
  def key_string(key) when is_atom(key), do: Atom.to_string(key)
  def key_string(key), do: inspect(key)

  @spec receipt(Receipt.t()) :: map()
  def receipt(%Receipt{} = receipt) do
    %{
      "id" => receipt.id,
      "sha256" => receipt.sha256,
      "plan_sha256" => receipt.plan_sha256,
      "catalog_sha256" => receipt.catalog_sha256,
      "contract_ids" => receipt.contract_ids,
      "observation_sha256_by_contract" => receipt.observation_sha256_by_contract,
      "evidence_sha256_by_contract" => receipt.evidence_sha256_by_contract,
      "result_sha256" => receipt.result_sha256,
      "row_count" => receipt.row_count,
      "previous" => receipt.previous,
      "authority" => Atom.to_string(receipt.authority),
      "standing" => Atom.to_string(receipt.standing),
      "signature" => receipt.signature
    }
  end

  @spec result(Result.t()) :: map()
  def result(%Result{} = result) do
    %{
      "plan_sha256" => result.plan_sha256,
      "rows" => result.rows,
      "row_count" => result.row_count,
      "sources" => result.sources,
      "sha256" => result.sha256,
      "standing" => Atom.to_string(result.standing)
    }
  end

  @spec session(Session.t()) :: map()
  def session(%Session{} = session) do
    %{
      "summary" => stringify(Session.summary(session)),
      "receipt" => receipt(session.receipt),
      "result" => result(session.result)
    }
  end

  @spec encode_receipt!(Receipt.t()) :: String.t()
  def encode_receipt!(%Receipt{} = receipt), do: receipt |> receipt() |> canonical_json()

  @spec encode_result!(Result.t()) :: String.t()
  def encode_result!(%Result{} = result), do: result |> result() |> canonical_json()

  @spec encode_session!(Session.t()) :: String.t()
  def encode_session!(%Session{} = session), do: session |> session() |> canonical_json()

  @doc "Decode a receipt JSON document. Structure only; use `verify_receipt_json/3` to verify."
  @spec decode_receipt(String.t()) :: {:ok, Receipt.t()} | {:error, Refusal.t()}
  def decode_receipt(json) when is_binary(json) do
    with {:ok, map} <- decode_object(json, :receipt),
         {:ok, authority} <- enum(map, "authority", [:NONE], :receipt),
         {:ok, standing} <- enum(map, "standing", Result.standings(), :receipt),
         :ok <- signature(map),
         :ok <-
           fields(
             map,
             ~w(id sha256 plan_sha256 catalog_sha256 contract_ids
                              observation_sha256_by_contract evidence_sha256_by_contract result_sha256 row_count),
             :receipt
           ) do
      {:ok,
       %Receipt{
         id: map["id"],
         sha256: map["sha256"],
         plan_sha256: map["plan_sha256"],
         catalog_sha256: map["catalog_sha256"],
         contract_ids: map["contract_ids"],
         observation_sha256_by_contract: map["observation_sha256_by_contract"],
         evidence_sha256_by_contract: map["evidence_sha256_by_contract"],
         result_sha256: map["result_sha256"],
         row_count: map["row_count"],
         previous: map["previous"],
         authority: authority,
         standing: standing,
         signature: map["signature"]
       }}
    end
  end

  def decode_receipt(other), do: refuse(:receipt, "receipt JSON must be a binary", %{got: inspect(other)})

  @doc "Decode a result JSON document. Structure only; digests are checked by `Result.verify/1`."
  @spec decode_result(String.t()) :: {:ok, Result.t()} | {:error, Refusal.t()}
  def decode_result(json) when is_binary(json) do
    with {:ok, map} <- decode_object(json, :result),
         {:ok, standing} <- enum(map, "standing", Result.standings(), :result),
         :ok <- fields(map, ~w(plan_sha256 rows row_count sha256), :result),
         true <- is_list(map["rows"]) or refuse(:result, "result rows must be a list", %{}) do
      {:ok,
       %Result{
         plan_sha256: map["plan_sha256"],
         rows: decode_value(map["rows"]),
         row_count: map["row_count"],
         sources: map["sources"] || %{},
         sha256: map["sha256"],
         standing: standing
       }}
    end
  end

  def decode_result(other), do: refuse(:result, "result JSON must be a binary", %{got: inspect(other)})

  @doc """
  Decode receipt and result JSON, then run the full replay verification against `plan`.

  `opts` are the `AshR2RML.VKG.Receipt.verify/5` options (`:key`, `:require_signature`).
  """
  @spec verify_receipt_json(String.t(), String.t(), AshR2RML.VKG.QueryPlan.t(), keyword()) ::
          :ok | {:error, Refusal.t()}
  def verify_receipt_json(receipt_json, result_json, plan, opts \\ []) do
    with {:ok, receipt} <- decode_receipt(receipt_json),
         {:ok, result} <- decode_result(result_json) do
      AshR2RML.VKG.Replay.verify(receipt, plan, result, nil, opts)
    end
  end

  @doc """
  Reverses the canonical tags on a decoded JSON value (`$atom`, `$date`, `$time`,
  `$naive_datetime`, `$datetime`, `$decimal`, `$tuple`, `$binary`, `$map`).

  Atoms are resolved with `String.to_existing_atom/1`, so decoding untrusted JSON
  cannot mint atoms; an unknown atom or malformed tag is left as the tagged map,
  which then fails digest verification. Untagged values are returned unchanged.
  """
  @spec decode_value(term()) :: term()
  def decode_value(list) when is_list(list), do: Enum.map(list, &decode_value/1)

  def decode_value(%{"$map" => inner} = map) when map_size(map) == 1 and is_map(inner),
    do: Map.new(inner, fn {k, v} -> {k, decode_value(v)} end)

  def decode_value(%{"$atom" => name} = map) when map_size(map) == 1 and is_binary(name) do
    String.to_existing_atom(name)
  rescue
    ArgumentError -> map
  end

  def decode_value(%{"$tuple" => items} = map) when map_size(map) == 1 and is_list(items),
    do: items |> Enum.map(&decode_value/1) |> List.to_tuple()

  def decode_value(%{"$decimal" => text} = map) when map_size(map) == 1 and is_binary(text) do
    case Decimal.parse(text) do
      {%Decimal{} = decimal, ""} -> decimal
      _ -> map
    end
  end

  def decode_value(%{"$binary" => text} = map) when map_size(map) == 1 and is_binary(text) do
    case Base.decode64(text) do
      {:ok, bin} -> bin
      :error -> map
    end
  end

  for {tag, module} <- [
        {"$date", Date},
        {"$time", Time},
        {"$naive_datetime", NaiveDateTime},
        {"$datetime", DateTime}
      ] do
    def decode_value(%{unquote(tag) => text} = map) when map_size(map) == 1 and is_binary(text) do
      case unquote(module).from_iso8601(text) do
        {:ok, value} -> value
        {:ok, value, _offset} -> value
        _ -> map
      end
    end
  end

  def decode_value(map) when is_map(map) and not is_struct(map),
    do: Map.new(map, fn {k, v} -> {k, decode_value(v)} end)

  def decode_value(other), do: other

  defp decode_object(json, subject) do
    case Jason.decode(json) do
      {:ok, map} when is_map(map) -> {:ok, map}
      {:ok, other} -> refuse(subject, "JSON document must be an object", %{got: inspect(other)})
      {:error, error} -> refuse(subject, "invalid JSON", %{error: Exception.message(error)})
    end
  end

  defp enum(map, key, allowed, subject) do
    case Enum.find(allowed, &(Atom.to_string(&1) == map[key])) do
      nil -> refuse(subject, "unsupported #{key}", %{value: inspect(map[key])})
      atom -> {:ok, atom}
    end
  end

  defp signature(%{"signature" => nil}), do: :ok
  defp signature(%{"signature" => sig}) when is_binary(sig), do: :ok
  defp signature(%{"signature" => other}), do: refuse(:receipt, "signature must be a string", %{got: inspect(other)})
  defp signature(_map), do: :ok

  defp fields(map, keys, subject) do
    case Enum.reject(keys, &(Map.get(map, &1) != nil)) do
      [] -> :ok
      missing -> refuse(subject, "missing required fields", %{missing: missing})
    end
  end

  defp refuse(subject, detail, evidence) do
    {:error, Refusal.new(:REFUSED_VKG_REPLAY, subject, detail, evidence)}
  end

  defp stringify(map), do: Map.new(map, fn {key, value} -> {key_string(key), value} end)

  # -- canonical encoder ----------------------------------------------------

  defp encode(nil), do: "null"
  defp encode(true), do: "true"
  defp encode(false), do: "false"
  defp encode(int) when is_integer(int), do: Integer.to_string(int)
  defp encode(float) when is_float(float), do: Jason.encode!(float)
  defp encode(atom) when is_atom(atom), do: tagged("$atom", Atom.to_string(atom))

  defp encode(bin) when is_binary(bin) do
    if String.valid?(bin), do: Jason.encode!(bin), else: tagged("$binary", Base.encode64(bin))
  end

  defp encode(list) when is_list(list) do
    if List.improper?(list),
      do: tagged("$improper_list", inspect(list)),
      else: ["[", list |> Enum.map(&encode/1) |> Enum.intersperse(","), "]"]
  end

  defp encode(tuple) when is_tuple(tuple), do: tagged("$tuple", Tuple.to_list(tuple))

  defp encode(%Date{} = date), do: tagged("$date", Date.to_iso8601(date))
  defp encode(%Time{} = time), do: tagged("$time", Time.to_iso8601(time))
  defp encode(%NaiveDateTime{} = naive), do: tagged("$naive_datetime", NaiveDateTime.to_iso8601(naive))
  defp encode(%DateTime{} = datetime), do: tagged("$datetime", DateTime.to_iso8601(datetime))
  defp encode(%Decimal{} = decimal), do: tagged("$decimal", Decimal.to_string(decimal))

  defp encode(%module{} = struct),
    do: struct |> Map.from_struct() |> Map.put("$struct", inspect(module)) |> encode_members()

  defp encode(map) when is_map(map) do
    cond do
      not plain_keys?(map) -> encode_pairs(map)
      reserved_keys?(map) -> ["{\"$map\":", encode_members(map), "}"]
      true -> encode_members(map)
    end
  end

  defp encode(other), do: tagged("$term", inspect(other))

  defp tagged(tag, value), do: encode_members(%{tag => value})

  # Keys are injective only when every key is a string or atom and no two keys
  # share a string form; anything else is spelled as explicit [key, value] pairs.
  defp plain_keys?(map) do
    keys = Map.keys(map)

    Enum.all?(keys, &(is_binary(&1) or is_atom(&1))) and
      length(keys) == keys |> Enum.map(&key_string/1) |> Enum.uniq() |> length()
  end

  defp encode_pairs(map) do
    pairs =
      map
      |> Enum.map(fn {key, value} -> canonical_json([key, value]) end)
      |> Enum.sort()

    ["{\"$pairs\":[", Enum.intersperse(pairs, ","), "]}"]
  end

  defp reserved_keys?(map), do: Enum.any?(map, fn {key, _} -> String.starts_with?(key_string(key), "$") end)

  defp encode_members(map) do
    members =
      map
      |> Enum.map(fn {key, value} -> {key_string(key), is_binary(key), value} end)
      |> Enum.sort_by(fn {key, binary_key?, _value} -> {key, not binary_key?} end)
      |> Enum.dedup_by(fn {key, _binary_key?, _value} -> key end)
      |> Enum.map(fn {key, _binary_key?, value} -> [Jason.encode!(key), ":", encode(value)] end)

    ["{", Enum.intersperse(members, ","), "}"]
  end
end
