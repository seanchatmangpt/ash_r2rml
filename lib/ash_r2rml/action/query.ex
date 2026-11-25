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
  `:max_rows`, `:max_triples`, `:timeout_ms`, `:allow_sensitive?`, `:require_authorizer` and
  `:require_tenant` are forwarded. Actor, tenant
  and authorize? come from the action context. The action returns a plain map with
  `:bindings`, `:triples`, `:stats` and `:digest`; a refusal is returned as `{:error, refusal}`.
  """

  use Ash.Resource.Actions.Implementation

  @forwarded [:max_rows, :max_triples, :timeout_ms, :allow_sensitive?, :require_authorizer, :require_tenant]
  @source_keys [:domain, :resources, :specs_fun]
  @known_keys @forwarded ++ @source_keys

  @doc false
  def init(opts) when is_list(opts) do
    case Keyword.keys(opts) -- @known_keys do
      [] -> validate_source(opts)
      unknown -> {:error, "unknown option(s) #{inspect(unknown)}; expected #{inspect(@known_keys)}"}
    end
  end

  def init(_opts), do: {:error, "options must be a keyword list"}

  defp validate_source(opts) do
    case opts[:specs_fun] do
      nil -> {:ok, opts}
      {m, f, a} when is_atom(m) and is_atom(f) and is_list(a) -> {:ok, opts}
      other -> {:error, ":specs_fun must be {module, function, args}, got #{inspect(other)}"}
    end
  end

  @impl true
  def run(input, opts, context) do
    sparql = Ash.ActionInput.get_argument(input, :sparql)

    with {:ok, source} <- source(opts, input),
         {:ok, result} <- AshR2RML.OBDA.query(source, sparql, query_opts(opts, input, context)) do
      {:ok, Map.take(result, [:bindings, :triples, :kind, :stats, :digest])}
    end
  end

  defp source(opts, input) do
    cond do
      opts[:specs_fun] ->
        {m, f, a} = opts[:specs_fun]
        {:ok, apply(m, f, a)}

      opts[:resources] ->
        {:ok, opts[:resources]}

      opts[:domain] ->
        {:ok, opts[:domain]}

      is_atom(input.domain) and not is_nil(input.domain) ->
        {:ok, input.domain}

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

  defp query_opts(opts, input, context) do
    authorize? = context.authorize? != false

    opts
    |> Keyword.take(@forwarded)
    |> Keyword.put(:actor, context.actor)
    |> Keyword.put(:tenant, context.tenant)
    |> Keyword.put(:authorize?, authorize?)
    |> put_unless(:allow_unauthorized, true, authorize?)
    |> put_present(:context, context.source_context)
    |> put_present(:domain, context.domain || input.domain)
  end

  # authorize?: false was requested explicitly by the caller of the action; the OBDA read
  # needs the matching explicit opt-in.
  defp put_unless(kw, _key, _value, true), do: kw
  defp put_unless(kw, key, value, false), do: Keyword.put(kw, key, value)

  defp put_present(kw, _key, nil), do: kw
  defp put_present(kw, key, value), do: Keyword.put(kw, key, value)
end
