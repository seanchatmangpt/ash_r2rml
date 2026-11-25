# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

AshR2RML.DataLayerContract.exclude_postgres_by_default!()

alias AshR2RML.CrossLayerEquivalenceAll.Fixture

require Fixture

Fixture.define AshR2RML.RefactorW6BoundsNil.Ets, Ash.DataLayer.Ets, [] do
  ets do
    private? false
  end
end

defmodule AshR2RML.RefactorW6BoundsNilTest do
  @moduledoc """
  A `nil` bound means "use the default"; it must never disable a bound, and a small explicit
  bound must still refuse, through the real `AshR2RML.OBDA.query/3`.
  """
  use ExUnit.Case, async: false

  alias AshR2RML.RefactorW6BoundsNil.Ets

  @sparql "SELECT ?s ?n WHERE { ?s <https://schema.org/name> ?n }"

  setup_all do
    resource = Module.concat(Ets, Person)
    domain = Module.concat(Ets, Domain)

    for {pid, name} <- [{"b1", "Ada"}, {"b2", "Grace"}, {"b3", "Edsger"}] do
      resource
      |> Ash.Changeset.for_create(:create, %{pid: pid, name: name, age: 1}, domain: domain)
      |> Ash.create!(domain: domain, authorize?: false)
    end

    :ok
  end

  defp run(extra) do
    resource = Module.concat(Ets, Person)
    domain = Module.concat(Ets, Domain)
    mapping = AshR2RML.Resource.Info.mapping!(resource)
    opts = [domain: domain, authorize?: false, allow_unauthorized: true] ++ extra
    AshR2RML.OBDA.query([{resource, mapping}], @sparql, opts)
  end

  test "nil max_rows and max_triples fall back to defaults and return the same rows" do
    assert {:ok, baseline} = run([])
    assert {:ok, result} = run(max_rows: nil, max_triples: nil)
    assert length(result.bindings) == 3
    assert result.bindings == baseline.bindings
    assert result.digest == baseline.digest
  end

  test "small explicit max_rows still refuses" do
    assert {:error, error} = run(max_rows: 1)
    assert error.code == :REFUSED_RESULT_LIMIT_EXCEEDED
  end

  test "small explicit max_triples still refuses" do
    assert {:error, error} = run(max_triples: 1)
    assert error.code == :REFUSED_TRIPLE_LIMIT_EXCEEDED
  end

  test "non-positive bounds are refused up front" do
    assert {:error, error} = run(max_rows: 0)
    assert error.code == :REFUSED_INVALID_OPTION
  end
end
