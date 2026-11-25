# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OBDA.Preflight do
  @moduledoc """
  Policy and tenant preflight for OBDA reads of one Ash resource.

  Results:

    * `:ok` - the read may proceed.
    * `:pruned` - the actor cannot read the resource at all (`Ash.can?/3` with
      `maybe_is: true` is false); the resource contributes no triples.
    * `{:error, %AshR2RML.Refusal{code: :REFUSED_INVALID_TERM_MAP}}` - the resource has no
      primary read action, or the requested `:action` is not a read action of it.
    * `{:error, %AshR2RML.Refusal{code: :REFUSED_MISSING_TENANT}}` - the resource is
      multitenant (`:attribute` / `:context`), is not `global?`, and no tenant was given.

  Tenant is checked before policy, so a missing tenant is refused rather than pruned.

  Options: `:actor`, `:tenant`, `:context`, `:action` (read action name, default: primary
  read), `:domain`. `:actor`, `:tenant`, `:context` and `:domain` are forwarded to `Ash.can?/3`
  exactly as the read path forwards them to `Ash.read/2`, so context-dependent policies
  answer identically in preflight and read. (`:authorize?` is not forwarded: the caller skips
  preflight when it is `false`.)
  """

  alias AshR2RML.Refusal

  @type result :: :ok | :pruned | {:error, Refusal.t()}

  @spec check(module(), keyword()) :: result()
  def check(resource, opts \\ []) when is_atom(resource) and is_list(opts) do
    actor = Keyword.get(opts, :actor)
    tenant = Keyword.get(opts, :tenant)

    with :ok <- check_tenant(resource, tenant) do
      check_policy(resource, actor, tenant, opts)
    end
  end

  defp check_tenant(resource, tenant) do
    strategy = Ash.Resource.Info.multitenancy_strategy(resource)

    if strategy in [:attribute, :context] and
         not Ash.Resource.Info.multitenancy_global?(resource) and is_nil(tenant) do
      {:error,
       Refusal.new(
         :REFUSED_MISSING_TENANT,
         resource,
         "multitenant resource #{inspect(resource)} requires a tenant",
         %{strategy: strategy}
       )}
    else
      :ok
    end
  end

  defp check_policy(resource, actor, tenant, opts) do
    action =
      Keyword.get(opts, :action) ||
        case Ash.Resource.Info.primary_action(resource, :read) do
          %{name: name} -> name
          _ -> nil
        end

    case action do
      nil ->
        {:error,
         Refusal.new(
           :REFUSED_INVALID_TERM_MAP,
           resource,
           "resource #{inspect(resource)} has no primary read action",
           %{}
         )}

      name ->
        policy_for_action(resource, name, actor, tenant, opts)
    end
  end

  defp policy_for_action(resource, name, actor, tenant, opts) do
    case Ash.Resource.Info.action(resource, name) do
      %{type: :read} ->
        can_opts =
          [tenant: tenant, maybe_is: true]
          |> put_context(Keyword.get(opts, :context))
          |> put_domain(Keyword.get(opts, :domain))

        if Ash.can?({resource, name}, actor, can_opts), do: :ok, else: :pruned

      _ ->
        {:error,
         Refusal.new(
           :REFUSED_INVALID_TERM_MAP,
           resource,
           "#{inspect(name)} is not a read action of #{inspect(resource)}",
           %{action: name}
         )}
    end
  end

  defp put_context(opts, nil), do: opts
  defp put_context(opts, context), do: Keyword.put(opts, :context, context)

  defp put_domain(opts, nil), do: opts
  defp put_domain(opts, domain), do: Keyword.put(opts, :domain, domain)
end
