# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Red2RescueControlFlowTest do
  use ExUnit.Case, async: true

  alias AshR2RML.OBDA
  alias AshR2RML.OBDA.InMemory.IriTemplate
  alias AshR2RML.Refusal

  # Expected row misses are data, not exceptions: they must not raise.
  defp attempt(fun) do
    {:returned, fun.()}
  rescue
    error -> {:raised, error}
  end

  describe "IriTemplate.substitute/2 expected row misses" do
    test "a nil field value does not raise" do
      result = attempt(fn -> IriTemplate.substitute("http://schema.org/{name}", %{name: nil}) end)
      refute match?({:raised, _}, result)
    end

    test "a missing key does not raise" do
      result = attempt(fn -> IriTemplate.substitute("http://schema.org/{name}", %{}) end)
      refute match?({:raised, _}, result)
    end

    test "a value without a lexical form does not raise" do
      result = attempt(fn -> IriTemplate.substitute("http://schema.org/{name}", %{name: %{a: 1}}) end)
      refute match?({:raised, _}, result)
    end

    test "a present value still substitutes and encodes" do
      assert IriTemplate.substitute("http://schema.org/{name}", %{name: "a>b"}) ==
               "http://schema.org/a%3Eb"
    end
  end

  describe "OBDA.resolve_specs/1 refusals" do
    test "a malformed list element is a typed refusal" do
      assert {:error, %Refusal{}} = OBDA.resolve_specs([123])
    end

    test "a malformed tuple element is a typed refusal" do
      assert {:error, %Refusal{}} = OBDA.resolve_specs([{"not an atom", :nope}])
    end

    test "a non-domain atom is a typed refusal" do
      assert {:error, %Refusal{}} = OBDA.resolve_specs(String)
    end

    test "an empty list is a typed refusal" do
      assert {:error, %Refusal{}} = OBDA.resolve_specs([])
    end
  end
end
