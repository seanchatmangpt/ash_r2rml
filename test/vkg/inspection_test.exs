defmodule AshR2RML.VKG.InspectionTest do
  use ExUnit.Case, async: true

  alias AshR2RML.VKG.{Inspection, Receipt, Session}

  test "catalog inspection exposes exact identities" do
    assert {:ok, catalog} = AshR2RML.VKG.catalog()
    view = Inspection.catalog(catalog)

    assert view.contract_count == 10
    assert byte_size(view.catalog_sha256) == 64

    assert Enum.all?(view.contracts, fn contract ->
             byte_size(contract.source_sha256) == 64 and
               byte_size(contract.mapping_sha256) == 64
           end)
  end

  test "session inspection carries stage observation identities" do
    assert {:ok, catalog} = AshR2RML.VKG.catalog()
    assert {:ok, plan} = AshR2RML.VKG.Planner.plan(catalog, ["customer"])

    assert {:ok, result, observations} =
             AshR2RML.VKG.Executor.execute(
               plan,
               engine: AshR2RML.VKGCase.FakeEngine
             )

    receipt = Receipt.build(plan, result, observations)
    session = Session.new(catalog, plan, result, observations, receipt)
    view = Inspection.session(session)

    assert view.replay == :ok

    assert [
             %{
               contract_id: "customer",
               observed?: true,
               observation_sha256: digest
             }
           ] = view.stages

    assert byte_size(digest) == 64
  end
end
