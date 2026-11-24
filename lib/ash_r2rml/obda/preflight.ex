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
    * `{:error, %AshR2RML.Refusal{code: :REFUSED_MISSING_TENANT}}` - the resource is
      multitenant (`:attribute` / `:context`), is not `global?`, and no tenant was given.

  Tenant is checked before policy, so a missing tenant is refused rather than pruned.

  Options: `:actor`, `:tenant`, `:action` (read action name, default: primary read),
  `:domain`.
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
        :pruned

      name ->
        can_opts =
          [tenant: tenant, maybe_is: true]
          |> put_domain(Keyword.get(opts, :domain))

        if Ash.can?({resource, name}, actor, can_opts), do: :ok, else: :pruned
    end
  end

  defp put_domain(opts, nil), do: opts
  defp put_domain(opts, domain), do: Keyword.put(opts, :domain, domain)
end
