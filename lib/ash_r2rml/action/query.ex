# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Action.Query do
  @moduledoc """
  `Ash.Resource.Actions.Implementation` that runs a SPARQL query through
  `AshR2RML.OBDA.query/3` as an Ash generic action.

      action :sparql, :map do
        argument :sparql, :string, allow_nil?: false
        run {AshR2RML.Action.Query, domain: MyApp.Domain}
      end

  Source options (one required): `:domain`, `:resources` (module list), or
  `:specs_fun` (an `{module, function, args}` returning `{resource, mapping}` specs).
  `:max_rows`, `:max_triples`, `:timeout_ms`, `:allow_sensitive?` are forwarded. Actor, tenant
  and authorize? come from the action context. The action returns a plain map with
  `:bindings`, `:triples`, `:stats` and `:digest`; a refusal is returned as `{:error, refusal}`.
  """

  use Ash.Resource.Actions.Implementation

  @forwarded [:max_rows, :max_triples, :timeout_ms, :allow_sensitive?]

  @impl true
  def run(input, opts, context) do
    sparql = Ash.ActionInput.get_argument(input, :sparql)

    with {:ok, source} <- source(opts),
         {:ok, result} <- unwrap(AshR2RML.OBDA.query(source, sparql, query_opts(opts, context))) do
      {:ok, Map.take(result, [:bindings, :triples, :kind, :stats, :digest])}
    end
  end

  # OBDA.query/3 routes through Worker.run/2, which wraps the inner `{:ok, _} | {:error, _}`
  # in another `{:ok, _}`; tolerate both the nested and the flat shape.
  defp unwrap({:ok, {:ok, result}}), do: {:ok, result}
  defp unwrap({:ok, {:error, reason}}), do: {:error, reason}
  defp unwrap(other), do: other

  defp source(opts) do
    cond do
      opts[:specs_fun] ->
        {m, f, a} = opts[:specs_fun]
        {:ok, apply(m, f, a)}

      opts[:resources] ->
        {:ok, opts[:resources]}

      opts[:domain] ->
        {:ok, opts[:domain]}

      true ->
        {:error,
         AshR2RML.Refusal.new(
           :REFUSED_UNSUPPORTED_SPARQL_FEATURE,
           __MODULE__,
           "action requires one of :domain, :resources or :specs_fun",
           %{}
         )}
    end
  end

  defp query_opts(opts, context) do
    opts
    |> Keyword.take(@forwarded)
    |> Keyword.put(:actor, context.actor)
    |> Keyword.put(:tenant, context.tenant)
    |> Keyword.put(:authorize?, context.authorize? != false)
  end
end
