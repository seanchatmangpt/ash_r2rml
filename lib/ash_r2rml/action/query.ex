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
  `:max_rows`, `:max_triples`, `:timeout_ms` (positive integers), `:allow_sensitive?` (alias
  `:allow_sensitive`), `:allow_unauthorized`, `:require_authorizer` and `:require_tenant` are forwarded. Actor,
  tenant and authorize? come from the action context; `authorize?: false` is refused unless
  the action itself opts in with `allow_unauthorized: true`. The action returns a plain map with
  `:bindings`, `:triples`, `:stats` and `:digest`; a refusal is returned as `{:error, refusal}`.
  """

  use Ash.Resource.Actions.Implementation

  @forwarded [
    :max_rows,
    :max_triples,
    :timeout_ms,
    :allow_sensitive?,
    :allow_sensitive,
    :allow_unauthorized,
    :require_authorizer,
    :require_tenant
  ]
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

  @bounds [:max_rows, :max_triples, :timeout_ms]

  defp validate_source(opts) do
    with :ok <- validate_specs_fun(opts[:specs_fun]),
         :ok <- validate_present(opts),
         :ok <- validate_bounds(opts) do
      {:ok, opts}
    end
  end

  defp validate_specs_fun(nil), do: :ok
  defp validate_specs_fun({m, f, a}) when is_atom(m) and is_atom(f) and is_list(a), do: :ok
  defp validate_specs_fun(other), do: {:error, ":specs_fun must be {module, function, args}, got #{inspect(other)}"}

  defp validate_present(opts) do
    if Enum.any?(@source_keys, &(opts[&1] != nil)),
      do: :ok,
      else: {:error, "one of #{inspect(@source_keys)} is required"}
  end

  defp validate_bounds(opts) do
    Enum.find_value(@bounds, :ok, fn key ->
      case Keyword.fetch(opts, key) do
        {:ok, value} when not (is_integer(value) and value > 0) ->
          {:error, "#{inspect(key)} must be a positive integer, got #{inspect(value)}"}

        _ ->
          nil
      end
    end)
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
           :REFUSED_INVALID_OPTION,
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
    |> put_present(:context, context.source_context)
    |> put_present(:domain, context.domain || input.domain)
  end

  defp put_present(kw, _key, nil), do: kw
  defp put_present(kw, key, value), do: Keyword.put(kw, key, value)
end
