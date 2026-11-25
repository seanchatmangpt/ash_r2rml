# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RedCompilerTest do
  @moduledoc """
  Red-before-green courts for audit findings H25 and H37 on `AshR2RML.Compiler`.
  """
  use ExUnit.Case, async: true

  alias AshR2RML.Compiler
  alias AshR2RML.GrandExample.{Domain, Organization}
  alias AshR2RML.Refusal

  @compiler_src Path.expand("../lib/ash_r2rml/compiler.ex", __DIR__)

  describe "H25 compile/2 boundary" do
    test "H25 unknown option keys are not silently ignored" do
      result =
        try do
          Compiler.compile(Organization, totally_bogus_option: true)
        rescue
          ArgumentError -> :argument_error
        end

      assert result == :argument_error or match?({:error, %Refusal{}}, result)
    end

    test "H25 non-module input is refused with a code other than missing subject map" do
      result =
        try do
          Compiler.compile("not a module")
        rescue
          ArgumentError -> :argument_error
        end

      case result do
        :argument_error -> :ok
        {:error, %Refusal{code: code}} -> refute code == :REFUSED_MISSING_SUBJECT_MAP
      end
    end

    test "H25 non-module list element is refused with a code other than missing subject map" do
      result =
        try do
          Compiler.compile([Organization, 42])
        rescue
          ArgumentError -> :argument_error
        end

      case result do
        :argument_error -> :ok
        {:error, %Refusal{code: code}} -> refute code == :REFUSED_MISSING_SUBJECT_MAP
      end
    end

    test "H25 compile/2 does not define the receipt cutover helpers" do
      refute function_exported?(Compiler, :cutover_ready?, 1)
    end
  end

  describe "H37 closure worklist" do
    test "H37 closure over a domain yields each resource exactly once" do
      assert {:ok, bundle} = Compiler.compile(Domain)
      ids = Enum.map(bundle.resources, & &1.ash_resource)
      assert ids == Enum.uniq(ids)
      assert Organization in ids
    end

    test "H37 do_closure filters seen resources before enqueuing and avoids list append" do
      src = File.read!(@compiler_src)
      refute src =~ "rest ++ destinations"
      refute src =~ "acc ++ mapped"
      refute src =~ "acc ++ [item]"
    end
  end
end
