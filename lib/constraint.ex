# SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Constraint do
  @moduledoc """
  Convenience helpers for creating the Neo4j uniqueness constraints that enforce a
  resource's `identities` at the database level (#20).

      # Create the constraints for every identity on a resource
      AshNeo4j.Constraint.create_constraints(AssignmentRelationship)

      # Review the Cypher without touching the database
      AshNeo4j.Constraint.constraint_statements(AssignmentRelationship)

  Consistent with AshNeo4j's "no automatic migrations" stance — like
  `AshNeo4j.Vector`, this is an ergonomic tool you call (e.g. from a start-up or
  release task), not run on boot. Statements use `IF NOT EXISTS`, so they are safe
  to run repeatedly.

  ## Unsupported identities are refused, not skipped

  An identity that can't be enforced — `nils_distinct?: false`, or a filtered
  identity (`where:`) — returns `{:error, %AshNeo4j.Error.UnsupportedIdentity{}}`
  and creates **nothing** for the resource (all-or-nothing). Skipping would leave
  the identity unenforced and permit the duplicate records the constraint exists to
  prevent. The same cases are refused at compile time by
  `AshNeo4j.Verifiers.VerifyIdentities`.

  ## Naming

  Each constraint is named `<label_lower>_<identity_name>`, e.g.
  `assignmentrelationship_unique_assignment`.
  """

  alias AshNeo4j.Cypher
  alias AshNeo4j.Error.UnsupportedIdentity
  alias AshNeo4j.Resource.Info, as: ResourceInfo

  @doc """
  Runs `CREATE CONSTRAINT … IF NOT EXISTS` for every identity on `resource`.

  Returns `{:ok, [%Bolty.Response{}]}` (one per identity, empty when the resource
  has none), or `{:error, %AshNeo4j.Error.UnsupportedIdentity{}}` if any identity
  can't be enforced — in which case nothing is created.
  """
  @spec create_constraints(Ash.Resource.t(), keyword()) ::
          {:ok, [Bolty.Response.t()]} | {:error, term()}
  def create_constraints(resource, _opts \\ []) do
    with {:ok, specs} <- specs(resource) do
      run_all(Enum.map(specs, &create_cypher/1))
    end
  end

  @doc """
  Runs `DROP CONSTRAINT … IF EXISTS` for every identity on `resource`. A no-op for
  absent constraints. Unsupported identities are refused (nothing was created for
  them to drop), consistent with `create_constraints/2`.
  """
  @spec drop_constraints(Ash.Resource.t(), keyword()) ::
          {:ok, [Bolty.Response.t()]} | {:error, term()}
  def drop_constraints(resource, _opts \\ []) do
    with {:ok, specs} <- specs(resource) do
      run_all(Enum.map(specs, &drop_cypher/1))
    end
  end

  @doc """
  Returns `{:ok, [statement]}` — the `CREATE CONSTRAINT` Cypher `create_constraints/2`
  would run — without touching the database, or `{:error, %UnsupportedIdentity{}}`.

      AshNeo4j.Constraint.constraint_statements(Post)
      #=> {:ok, ["CREATE CONSTRAINT post_unique_unique IF NOT EXISTS FOR (n:Post) REQUIRE n.unique IS UNIQUE"]}
  """
  @spec constraint_statements(Ash.Resource.t()) :: {:ok, [String.t()]} | {:error, term()}
  def constraint_statements(resource) do
    with {:ok, specs} <- specs(resource), do: {:ok, Enum.map(specs, &create_cypher/1)}
  end

  # --- resolution --------------------------------------------------------

  # Resolves every identity to a constraint spec, or refuses the first one that
  # can't be enforced (all-or-nothing).
  defp specs(resource) do
    label = ResourceInfo.module_label(resource)
    translations = ResourceInfo.translations(resource)

    Enum.reduce_while(Ash.Resource.Info.identities(resource), {:ok, []}, fn identity, {:ok, acc} ->
      case spec(resource, label, translations, identity) do
        {:ok, spec} -> {:cont, {:ok, [spec | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, specs} -> {:ok, Enum.reverse(specs)}
      error -> error
    end
  end

  defp spec(resource, _label, _translations, %{where: where} = identity) when where != nil do
    {:error, UnsupportedIdentity.exception(resource: resource, identity: identity.name, keys: identity.keys, reason: :filtered)}
  end

  defp spec(resource, _label, _translations, %{nils_distinct?: false} = identity) do
    {:error,
     UnsupportedIdentity.exception(resource: resource, identity: identity.name, keys: identity.keys, reason: :nils_not_distinct)}
  end

  defp spec(_resource, label, translations, identity) do
    properties = Enum.map(identity.keys, fn key -> to_string(Keyword.get(translations, key, key)) end)

    {:ok,
     %{
       name: "#{label |> to_string() |> String.downcase()}_#{identity.name}",
       label: label,
       properties: properties
     }}
  end

  # --- cypher ------------------------------------------------------------

  defp create_cypher(%{name: name, label: label, properties: properties}) do
    "CREATE CONSTRAINT #{name} IF NOT EXISTS FOR (n:#{label}) REQUIRE #{require_clause(properties)} IS UNIQUE"
  end

  defp drop_cypher(%{name: name}), do: "DROP CONSTRAINT #{name} IF EXISTS"

  defp require_clause([property]), do: "n.#{property}"
  defp require_clause(properties), do: "(" <> Enum.map_join(properties, ", ", &"n.#{&1}") <> ")"

  defp run_all(statements) do
    Enum.reduce_while(statements, {:ok, []}, fn cypher, {:ok, acc} ->
      case Cypher.run(cypher) do
        {:ok, response} -> {:cont, {:ok, [response | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, responses} -> {:ok, Enum.reverse(responses)}
      error -> error
    end
  end
end
