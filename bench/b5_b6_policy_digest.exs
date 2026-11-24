# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# B5: policy overhead for admin vs member vs outsider actors through AshR2RML.OBDA.query/3.
# B6: canonical digest cost (AshR2RML.OBDA.Result.canonical_sort/1 is excluded; digest/3 is timed)
#     for 1k / 10k / 50k bindings.
#
# Run: mix run bench/b5_b6_policy_digest.exs
# Exits 1 when a budget is violated.

defmodule Bench.B5B6.Dom do
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource Bench.B5B6.Doc
  end
end

defmodule Bench.B5B6.Doc do
  use Ash.Resource,
    domain: Bench.B5B6.Dom,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer]

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:pid, :title]
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :member)
    end

    policy action_type(:create) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :pid, :string, public?: true
    attribute :title, :string, public?: true
  end
end

defmodule Bench.B5B6 do
  alias AshR2RML.Mapping.{LogicalTable, ObjectMap, PredicateObjectMap, Resource, SubjectMap}
  alias AshR2RML.OBDA
  alias AshR2RML.OBDA.Result

  @ex "https://ex.org/"
  @title "https://schema.org/name"
  @docs 200
  @rounds 15
  @select "SELECT ?t WHERE { ?s <#{@title}> ?t }"

  def run do
    failures = b5() ++ b6()

    case failures do
      [] ->
        IO.puts("B5/B6 PASS")

      _ ->
        Enum.each(failures, &IO.puts("FAIL: " <> &1))
        System.halt(1)
    end
  end

  defp mapping do
    %Resource{
      ash_resource: Bench.B5B6.Doc,
      logical_table: %LogicalTable{table_name: "doc"},
      subject_map: %SubjectMap{strategy: :template, value: @ex <> "doc/{pid}"},
      class_iris: [@ex <> "Doc"],
      identities: [[:pid]],
      predicate_object_maps: [
        %PredicateObjectMap{
          attribute: :title,
          predicate_iri: @title,
          object_map: %ObjectMap{strategy: :column, value: "title"}
        }
      ]
    }
  end

  defp specs, do: [{Bench.B5B6.Doc, mapping()}]

  defp seed do
    Ash.DataLayer.Ets.stop(Bench.B5B6.Doc)

    for i <- 1..@docs do
      Bench.B5B6.Doc
      |> Ash.Changeset.for_create(:create, %{pid: "d#{i}", title: "Title #{i}"},
        domain: Bench.B5B6.Dom,
        authorize?: false
      )
      |> Ash.create!(domain: Bench.B5B6.Dom, authorize?: false)
    end
  end

  defp actor(role), do: %{role: role}

  defp query(role) do
    {us, res} =
      :timer.tc(fn ->
        OBDA.query(specs(), @select, domain: Bench.B5B6.Dom, actor: actor(role))
      end)

    {us, res}
  end

  # min-of-N wall time in microseconds, last result retained
  defp measure(fun) do
    Enum.reduce(1..@rounds, {nil, nil}, fn _, {best, _last} ->
      {us, res} = fun.()
      {if(best == nil or us < best, do: us, else: best), res}
    end)
  end

  defp b5 do
    seed()

    {admin_us, admin} = measure(fn -> query(:admin) end)
    {member_us, member} = measure(fn -> query(:member) end)
    {outsider_us, outsider} = measure(fn -> query(:outsider) end)

    IO.puts("B5 admin   min=#{admin_us}us #{summary(admin)}")
    IO.puts("B5 member  min=#{member_us}us #{summary(member)}")
    IO.puts("B5 outsider min=#{outsider_us}us #{summary(outsider)}")
    IO.puts("B5 member/admin ratio=#{Float.round(member_us / max(admin_us, 1), 2)}")

    admin_ok =
      case admin do
        {:ok, %Result{stats: %{rows_read: @docs}}} -> []
        other -> ["B5 admin did not read #{@docs} subjects: #{inspect(other, limit: 5)}"]
      end

    member_ok =
      case member do
        {:ok, %Result{stats: %{rows_read: @docs, resources_pruned_by_policy: 0}}} -> []
        other -> ["B5 member did not read #{@docs} subjects: #{inspect(other, limit: 5)}"]
      end

    outsider_ok =
      case outsider do
        {:ok, %Result{stats: %{rows_read: 0, resources_pruned_by_policy: pruned}}} when pruned >= 1 ->
          if outsider_us <= 2_000,
            do: [],
            else: ["B5 outsider #{outsider_us}us exceeds 2000us budget"]

        other ->
          ["B5 outsider expected rows_read 0 and pruned >= 1: #{inspect(other, limit: 5)}"]
      end

    admin_ok ++ member_ok ++ outsider_ok
  end

  defp summary({:ok, %Result{stats: s}}), do: inspect(Map.take(s, [:rows_read, :resources_pruned_by_policy]))
  defp summary(other), do: "non-ok " <> inspect(other, limit: 3)

  defp rows(n), do: for(i <- 1..n, do: %{"s" => @ex <> "doc/d#{i}", "t" => "Title #{i}"})

  defp b6 do
    ttl = String.duplicate("<a> <b> <c> .\n", 50)

    Enum.flat_map([{1_000, nil}, {10_000, 20_000}, {50_000, nil}], fn {n, budget_us} ->
      sorted = n |> rows() |> Result.canonical_sort()

      {best, digest} =
        Enum.reduce(1..@rounds, {nil, nil}, fn _, {best, _} ->
          {us, d} = :timer.tc(fn -> Result.digest(ttl, @select, sorted) end)
          {if(best == nil or us < best, do: us, else: best), d}
        end)

      IO.puts("B6 n=#{n} digest min=#{best}us digest=#{String.slice(digest, 0, 12)}")

      if budget_us && best > budget_us,
        do: ["B6 n=#{n} digest #{best}us exceeds #{budget_us}us budget"],
        else: []
    end)
  end
end

Bench.B5B6.run()
