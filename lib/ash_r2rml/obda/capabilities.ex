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

  # Query-level capabilities requested by callers such as the VKG executor. They
  # are a separate vocabulary from the R2RML mapping features above; Ontop answers
  # SPARQL select/filter/join/aggregate at every supported version.
  @query_capabilities [:select, :filter, :join, :aggregate]

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
    supported = supported(engine, version) ++ query_supported(engine)
    unknown_standard = required -- (@w3c ++ @query_capabilities)
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

  defp query_supported(engine) when engine in [:ontop, "ontop"], do: @query_capabilities
  defp query_supported(_engine), do: []

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
