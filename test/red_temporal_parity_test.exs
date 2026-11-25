# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RedTemporalParityTest do
  @moduledoc """
  H20 temporal NewType refusal propagation; H21 parity canonical struct identity.
  """
  use ExUnit.Case, async: true

  # A true cycle cannot compile (`use` needs the subtype loaded), so build a chain
  # deeper than the unwrapper's depth bound (16); it yields the same typed refusal.
  @chain (for i <- 1..20, reduce: [Ash.Type.UtcDatetime] do
            [prev | _] = acc ->
              name = Module.concat(__MODULE__, "Deep#{i}")

              Module.create(
                name,
                quote do
                  use Ash.Type.NewType, subtype_of: unquote(prev)
                end,
                Macro.Env.location(__ENV__)
              )

              [name | acc]
          end)

  @deep hd(@chain)
  @deeper Module.concat(__MODULE__, "Deep19")

  def deep, do: @deep
  def deeper, do: @deeper

  test "H20 cyclic NewType start attribute propagates the unwrap refusal" do
    lookup = fn :starts -> {:ok, deep(), "starts"} end
    entry = %{start_attribute: :starts, end_attribute: nil}

    assert {:error, %AshR2RML.Refusal{} = refusal} = AshR2RML.Temporal.compile(entry, lookup)
    assert refusal.code == :UNSUPPORTED_ASH_TYPE
    assert refusal.evidence[:normalized_type] == :newtype_cycle
  end

  test "H20 cyclic NewType end attribute propagates the unwrap refusal" do
    lookup = fn :ends -> {:ok, deeper(), "ends"} end
    entry = %{start_attribute: nil, end_attribute: :ends}

    assert {:error, %AshR2RML.Refusal{code: code}} = AshR2RML.Temporal.compile(entry, lookup)
    assert code == :UNSUPPORTED_ASH_TYPE
  end

  test "H21 ForbiddenField, NotLoaded and a plain map normalize to distinct values" do
    forbidden = struct(Ash.ForbiddenField, field: :name, type: :attribute)
    not_loaded = struct(Ash.NotLoaded, field: :name, type: :attribute)
    plain = %{field: :name, type: :attribute}

    [f] = AshR2RML.Parity.normalize_multiset([%{"v" => forbidden}])
    [n] = AshR2RML.Parity.normalize_multiset([%{"v" => not_loaded}])
    [p] = AshR2RML.Parity.normalize_multiset([%{"v" => plain}])

    refute f == n
    refute f == p
    refute n == p
  end
end
