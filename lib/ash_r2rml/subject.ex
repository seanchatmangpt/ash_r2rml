# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Subject do
  @moduledoc """
  Pure conversion between record key values and subject IRIs for template subject maps.

  `to_iri/2` substitutes percent-encoded attribute values into the subject template
  (byte-identical to `AshR2RML.OBDA.InMemory`: `URI.encode/2` with `URI.char_unreserved?/1`).
  `from_iri/2` inverts the template and refuses any template or IRI whose inversion is not
  exact (the captured values must re-encode to the very same IRI).

  Only the `:template` subject strategy is supported; other strategies refuse with
  `:UNSUPPORTED_TERM_TYPE`.

  ## Examples

      iex> alias AshR2RML.Mapping.{LogicalTable, Resource, SubjectMap}
      iex> mapping = %Resource{
      ...>   ash_resource: "Person",
      ...>   logical_table: %LogicalTable{table_name: "people"},
      ...>   subject_map: %SubjectMap{strategy: :template, value: "http://ex.org/p/{id}"}
      ...> }
      iex> AshR2RML.Subject.to_iri(mapping, %{id: "a b"})
      {:ok, "http://ex.org/p/a%20b"}
      iex> AshR2RML.Subject.from_iri(mapping, "http://ex.org/p/a%20b")
      {:ok, %{id: "a b"}}
  """

  alias AshR2RML.Mapping.Resource, as: MappingResource
  alias AshR2RML.Mapping.SubjectMap
  alias AshR2RML.Refusal

  @type source :: MappingResource.t() | module()
  @type segment :: {:lit, String.t()} | {:field, atom()}

  @placeholder ~r/(\{[a-zA-Z0-9_]+\})/

  @doc """
  Builds the subject IRI for `record_or_keys` (struct, map, or keyword list of attribute values).

  Refuses when the subject map is not a template, a template field is missing or nil, or a
  value cannot be rendered as a string.
  """
  @spec to_iri(source(), struct() | map() | keyword()) ::
          {:ok, String.t()} | {:error, Refusal.t()}
  def to_iri(source, record_or_keys) do
    with {:ok, mapping, template} <- template(source),
         {:ok, segments} <- parse(mapping, template) do
      render(mapping, segments, record_or_keys)
    end
  end

  @doc """
  Inverts the subject template: returns `{:ok, %{field => decoded_value}}` for an IRI that
  `to_iri/2` could have produced, or a refusal for non-invertible templates and mismatches.
  """
  @spec from_iri(source(), String.t()) ::
          {:ok, %{atom() => String.t()}} | {:error, Refusal.t()}
  def from_iri(source, iri) when is_binary(iri) do
    with {:ok, mapping, template} <- template(source),
         {:ok, segments} <- parse(mapping, template),
         :ok <- check_separators(mapping, segments),
         {:ok, values} <- capture(mapping, segments, iri) do
      verify_roundtrip(mapping, segments, values, iri)
    end
  end

  def from_iri(source, iri) do
    with {:ok, mapping, _template} <- template(source) do
      {:error, refuse(mapping, :REFUSED_INVALID_TERM_MAP, "IRI must be a string", %{iri: iri})}
    end
  end

  @doc """
  Pure admission predicate: `true` only when the subject map term type is `:iri` and no
  predicate/object map or reference object map uses a `:blank_node` term type.
  """
  @spec iri_only?(source()) :: boolean()
  def iri_only?(source), do: check_iri_only(source) == :ok

  @doc """
  Like `iri_only?/1` but returns `{:error, %AshR2RML.Refusal{code: :UNSUPPORTED_TERM_TYPE}}`
  naming the offending term map. Unresolvable resources return the resolution refusal
  (same shape `to_iri/2` returns).
  """
  @spec check_iri_only(source()) :: :ok | {:error, Refusal.t()}
  def check_iri_only(source) do
    with {:ok, %MappingResource{} = mapping} <- resolve(source) do
      case blank_node_site(mapping) do
        nil ->
          :ok

        {where, evidence} ->
          {:error,
           refuse(
             mapping,
             :UNSUPPORTED_TERM_TYPE,
             "blank-node term type configured on #{where}; wire-level admission is IRI-only",
             evidence
           )}
      end
    end
  end

  defp resolve(%MappingResource{} = m), do: {:ok, m}
  defp resolve(resource) when is_atom(resource), do: AshR2RML.Resource.Info.mapping_result(resource)

  defp blank_node_site(%MappingResource{} = m) do
    cond do
      subject_blank?(m.subject_map) ->
        {"subject map", %{term_type: m.subject_map && m.subject_map.term_type}}

      pom = Enum.find(m.predicate_object_maps, &(object_term(&1) == :blank_node)) ->
        {"object map", %{predicate_iri: pom.predicate_iri, term_type: :blank_node}}

      rom = Enum.find(m.reference_object_maps, &(Map.get(&1, :term_type) == :blank_node)) ->
        {"reference object map", %{predicate_iri: rom.predicate_iri, term_type: :blank_node}}

      true ->
        nil
    end
  end

  defp subject_blank?(%SubjectMap{term_type: :iri}), do: false
  defp subject_blank?(_), do: true

  defp object_term(%{object_map: %{term_type: t}}), do: t
  defp object_term(_), do: nil

  # -- mapping resolution ---------------------------------------------------------------

  defp template(%MappingResource{subject_map: %SubjectMap{strategy: :template, value: t}} = m)
       when is_binary(t),
       do: {:ok, m, t}

  defp template(%MappingResource{subject_map: %SubjectMap{strategy: strategy}} = m) do
    {:error,
     refuse(
       m,
       :UNSUPPORTED_TERM_TYPE,
       "subject strategy #{inspect(strategy)} has no invertible template",
       %{strategy: strategy}
     )}
  end

  defp template(resource) when is_atom(resource) do
    case AshR2RML.Resource.Info.mapping_result(resource) do
      {:ok, %MappingResource{} = mapping} -> template(mapping)
      {:error, %Refusal{}} = error -> error
    end
  end

  # -- template parsing -----------------------------------------------------------------

  @spec parse(MappingResource.t(), String.t()) :: {:ok, [segment()]} | {:error, Refusal.t()}
  defp parse(mapping, template) do
    segments =
      @placeholder
      |> Regex.split(template, include_captures: true, trim: true)
      |> Enum.map(&to_segment/1)

    if Enum.any?(segments, &(&1 == :error)) do
      {:error, refuse(mapping, :REFUSED_INVALID_TERM_MAP, "unknown template field", %{template: template})}
    else
      {:ok, segments}
    end
  end

  defp to_segment(chunk) do
    case Regex.run(~r/\A\{([a-zA-Z0-9_]+)\}\z/, chunk, capture: :all_but_first) do
      [name] ->
        try do
          {:field, String.to_existing_atom(name)}
        rescue
          ArgumentError -> :error
        end

      nil ->
        {:lit, chunk}
    end
  end

  # -- rendering ------------------------------------------------------------------------

  defp render(mapping, segments, record) do
    Enum.reduce_while(segments, {:ok, []}, fn
      {:lit, text}, {:ok, acc} ->
        {:cont, {:ok, [text | acc]}}

      {:field, field}, {:ok, acc} ->
        case fetch(record, field) do
          {:ok, value} -> {:cont, {:ok, [encode(value) | acc]}}
          :error -> {:halt, {:error, missing(mapping, field)}}
        end
    end)
    |> case do
      {:ok, acc} -> {:ok, acc |> Enum.reverse() |> IO.iodata_to_binary()}
      {:error, _} = error -> error
    end
  end

  defp fetch(record, field) do
    value =
      cond do
        is_list(record) -> Keyword.get(record, field)
        is_map(record) -> Map.get(record, field, Map.get(record, Atom.to_string(field)))
        true -> nil
      end

    cond do
      is_nil(value) -> :error
      is_struct(value) and is_nil(String.Chars.impl_for(value)) -> :error
      true -> {:ok, value}
    end
  end

  defp encode(value), do: value |> to_string() |> percent_encode()

  defp percent_encode(value), do: URI.encode(value, &URI.char_unreserved?/1)

  defp missing(mapping, field) do
    refuse(
      mapping,
      :REFUSED_INVALID_TERM_MAP,
      "subject template field #{inspect(field)} is missing or nil",
      %{field: field}
    )
  end

  # -- inversion ------------------------------------------------------------------------

  defp check_separators(mapping, segments) do
    adjacent? =
      segments
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.any?(fn [a, b] -> match?({:field, _}, a) and match?({:field, _}, b) end)

    if adjacent? do
      {:error,
       refuse(
         mapping,
         :REFUSED_INVALID_TERM_MAP,
         "subject template has adjacent placeholders with no separator; not invertible",
         %{}
       )}
    else
      :ok
    end
  end

  defp capture(mapping, segments, iri), do: capture(mapping, segments, iri, iri, %{})

  defp capture(_m, [], "", _iri, acc), do: {:ok, acc}
  defp capture(m, [], _rest, iri, _acc), do: {:error, mismatch(m, iri, "trailing characters")}

  defp capture(m, [{:lit, text} | tail], rest, iri, acc) do
    case rest do
      <<^text::binary-size(byte_size(text)), more::binary>> -> capture(m, tail, more, iri, acc)
      _ -> {:error, mismatch(m, iri, "literal #{inspect(text)} not found")}
    end
  end

  defp capture(m, [{:field, field} | tail], rest, iri, acc) do
    with {:ok, raw, more} <- take(m, tail, rest, iri),
         {:ok, decoded} <- decode(m, raw, iri) do
      capture(m, tail, more, iri, Map.put(acc, field, decoded))
    end
  end

  defp take(m, [], rest, iri), do: nonempty(m, rest, "", iri)

  defp take(m, [{:lit, text} | _], rest, iri) do
    case :binary.match(rest, text) do
      {pos, _len} ->
        <<raw::binary-size(pos), more::binary>> = rest
        nonempty(m, raw, more, iri)

      :nomatch ->
        {:error, mismatch(m, iri, "separator #{inspect(text)} not found")}
    end
  end

  defp nonempty(m, "", _more, iri), do: {:error, mismatch(m, iri, "empty field capture")}
  defp nonempty(_m, raw, more, _iri), do: {:ok, raw, more}

  defp decode(m, raw, iri) do
    {:ok, URI.decode(raw)}
  rescue
    ArgumentError -> {:error, mismatch(m, iri, "malformed percent-encoding")}
  end

  defp verify_roundtrip(mapping, segments, values, iri) do
    case render(mapping, segments, values) do
      {:ok, ^iri} ->
        {:ok, values}

      _ ->
        {:error,
         refuse(
           mapping,
           :REFUSED_INVALID_TERM_MAP,
           "captured values do not re-encode to the same IRI; template is not invertible here",
           %{iri: iri}
         )}
    end
  end

  defp mismatch(mapping, iri, why) do
    refuse(
      mapping,
      :REFUSED_INVALID_TERM_MAP,
      "IRI does not match subject template: #{why}",
      %{iri: iri}
    )
  end

  defp refuse(%MappingResource{ash_resource: subject}, code, detail, evidence),
    do: Refusal.new(code, subject, detail, evidence)
end
