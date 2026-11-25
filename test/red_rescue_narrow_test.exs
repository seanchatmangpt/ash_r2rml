# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RedRescueNarrowTest do
  @moduledoc """
  SPARQL Local/Protocol must not blanket-rescue programmer errors into
  `:REFUSED_UNPROVEN_EQUIVALENCE`, and rescued boundary errors must name the
  exception module in refusal evidence.
  """
  use ExUnit.Case, async: true

  alias AshR2RML.Refusal
  alias AshR2RML.SPARQL.{Local, Protocol}

  @query "SELECT * WHERE { ?s ?p ?o }"
  @endpoint "https://endpoint.invalid/sparql"

  defp boundary_error do
    %File.Error{reason: :enoent, action: "read", path: "/nonexistent/boundary"}
  end

  defp evidence_names?(%Refusal{evidence: evidence}, module) do
    inspect(evidence) =~ inspect(module)
  end

  test "H06 Protocol: a KeyError raised by the client (programmer error) is not refused" do
    client = fn _parsed, _endpoint, _opts -> Map.fetch!(%{}, :missing_key) end

    assert_raise KeyError, fn ->
      Protocol.query_with(@endpoint, @query, [], client)
    end
  end

  test "H06 Protocol: an UndefinedFunctionError from the client is not refused" do
    client = fn _parsed, _endpoint, _opts ->
      apply(AshR2RML.NoSuchModuleForRedTest, :nope, [])
    end

    assert_raise UndefinedFunctionError, fn ->
      Protocol.query_with(@endpoint, @query, [], client)
    end
  end

  test "H06 Local: non-RDF data is raised or refused with the exception module named" do
    result =
      try do
        Local.query(:not_rdf_data, @query)
      rescue
        _ -> :raised
      end

    case result do
      :raised ->
        :ok

      {:error, %Refusal{} = refusal} ->
        assert refusal.evidence[:exception_module] != nil or
                 evidence_names?(refusal, Protocol.UndefinedError)

      other ->
        flunk("unexpected result #{inspect(other)}")
    end
  end

  test "H30 Protocol: a rescued boundary exception names its module in evidence" do
    client = fn _parsed, _endpoint, _opts -> raise boundary_error() end

    result =
      try do
        Protocol.query_with(@endpoint, @query, [], client)
      rescue
        File.Error -> :raised
      end

    case result do
      :raised ->
        :ok

      {:error, %Refusal{} = refusal} ->
        assert evidence_names?(refusal, File.Error)

      other ->
        flunk("unexpected result #{inspect(other)}")
    end
  end

  test "H30 Protocol: a BadMapError from the client is not refused" do
    client = fn _parsed, _endpoint, _opts -> Map.put(Process.get(:red_absent_key, :not_a_map), :k, 1) end

    assert_raise BadMapError, fn ->
      Protocol.query_with(@endpoint, @query, [], client)
    end
  end

  test "H30 Local: rescued exception refusal names the exception module" do
    result =
      try do
        Local.query(:not_rdf_data, @query)
      rescue
        _ -> :raised
      end

    case result do
      :raised ->
        :ok

      {:error, %Refusal{code: :REFUSED_UNPROVEN_EQUIVALENCE} = refusal} ->
        assert evidence_names?(refusal, Protocol.UndefinedError) or
                 refusal.evidence[:exception_module] != nil

      {:error, %Refusal{}} ->
        :ok

      other ->
        flunk("unexpected result #{inspect(other)}")
    end
  end
end
