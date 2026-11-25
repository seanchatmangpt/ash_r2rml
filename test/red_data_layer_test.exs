# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RedDataLayerTest do
  @moduledoc """
  Red-before-green courts for `AshR2RML.DataLayer`: no fabricated table names,
  no silent `:id` join columns, ETS table via the real Info module.
  """
  use ExUnit.Case, async: false

  alias AshR2RML.Introspection

  defmodule Owner do
    @moduledoc false
    use Ash.Resource,
      domain: AshR2RML.RedDataLayerTest.Dom,
      data_layer: Ash.DataLayer.Ets,
      validate_domain_inclusion?: false

    ets do
      private?(false)
      table(:red_dl_custom_owner_tbl)
    end

    actions do
      defaults([:read])
    end

    attributes do
      uuid_primary_key(:id)
    end
  end

  defmodule Child do
    @moduledoc false
    use Ash.Resource,
      domain: AshR2RML.RedDataLayerTest.Dom,
      data_layer: Ash.DataLayer.Ets,
      validate_domain_inclusion?: false

    ets do
      private?(false)
    end

    actions do
      defaults([:read])
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:owner_id, :uuid, public?: true, source: :owner_ref)
    end

    relationships do
      belongs_to :owner, Owner do
        source_attribute(:owner_id)
        attribute_writable?(true)
      end
    end
  end

  defmodule Dom do
    @moduledoc false
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource(Owner)
      resource(Child)
    end
  end

  defmodule PlainThing do
    @moduledoc false
    # Not an Ash resource: backend is :unknown, table is unknowable.
    def hello, do: :world
  end

  # FIXTURE-DEFECT repair: the court targeted AshR2RML.DataLayer, which is consolidated into
  # AshR2RML.Introspection; the same intent now binds the single source of truth.
  @source Path.expand("../lib/ash_r2rml/introspection.ex", __DIR__)

  test "H03 unknown backend does not fabricate a pluralized table name" do
    result = Introspection.table_name(PlainThing)
    refute result == "plain_things"
    refute is_binary(result)
  end

  test "H03 missing relationship join attributes are not silently defaulted to id" do
    result = Introspection.join_columns(Child, %{})
    refute result == {"id", "id"}
    refute result == {:ok, {"id", "id"}}
  end

  test "H03 postgres dispatch is guarded by Code.ensure_loaded?" do
    src = File.read!(@source)

    assert src =~ "Code.ensure_loaded?(info)"
  end

  test "H11 source holds no compile-time reference to AshPostgres.DataLayer" do
    src = File.read!(@source)
    refute src =~ ~r/^\s*AshPostgres\.DataLayer\s*->/m
  end

  test "H11 ETS table name comes from the resource's declared ets table" do
    assert Introspection.backend(Owner) == :ets
    assert Introspection.table_name(Owner) == {:ok, "red_dl_custom_owner_tbl"}
  end

  test "H11 join columns honor attribute source remapping" do
    rel = Ash.Resource.Info.relationship(Child, :owner)
    assert {:ok, {"owner_ref", _dest}} = Introspection.join_columns(Child, rel)
  end

  test "H24 unknown backend table is refused, not guessed" do
    result = Introspection.table_name(PlainThing)
    refute result == "plain_things"
    assert match?({:error, %AshR2RML.Refusal{}}, result)
  end

  test "H24 relationship with no source attribute is refused, not id-guessed" do
    result = Introspection.join_columns(Child, %{destination_attribute: :id})
    assert match?({:error, %AshR2RML.Refusal{}}, result)
  end

  test "H24 join columns respect attr.source for the source attribute" do
    rel = Ash.Resource.Info.relationship(Child, :owner)
    {:ok, {child_col, _}} = Introspection.join_columns(Child, rel)
    refute child_col == "owner_id"
  end
end
