# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RedVerifierInfoTest do
  @moduledoc """
  Red-before-green courts for H10 and H35: an unloadable module must not be
  reported as an unmapped resource, and the domain verifier must not silently
  admit a member it could not introspect.
  """
  use ExUnit.Case, async: true

  alias AshR2RML.Domain.Verifier
  alias AshR2RML.Refusal
  alias AshR2RML.Resource.Info

  defp outcome(fun) do
    {:returned, fun.()}
  rescue
    exception -> {:raised, exception}
  end

  defp masked_as_unmapped?({:returned, {:error, %Refusal{code: :REFUSED_MISSING_SUBJECT_MAP}}}),
    do: true

  defp masked_as_unmapped?(_), do: false

  test "H35 mapping_result does not report a never-compiled module as unmapped" do
    result = outcome(fn -> Info.mapping_result(AshR2RML.RedVerifierInfo.NeverCompiled) end)
    refute masked_as_unmapped?(result)
  end

  test "H35 mapping_result does not report a non-module atom as unmapped" do
    result = outcome(fn -> Info.mapping_result(:red_verifier_info_not_a_module) end)
    refute masked_as_unmapped?(result)
  end

  test "H35 mapping_result still refuses a loaded non-Spark module as unmapped" do
    assert {:error, %Refusal{code: :REFUSED_MISSING_SUBJECT_MAP}} = Info.mapping_result(Enum)
  end

  test "H35 sparql_queries does not silently return [] for a never-compiled module" do
    result = outcome(fn -> Info.sparql_queries(AshR2RML.RedVerifierInfo.NeverCompiled) end)
    refute result == {:returned, []}
  end

  test "H10 domain verifier does not admit a member module that is not compiled" do
    missing = AshR2RML.RedVerifierInfo.MissingMember

    dsl = %{
      :persist => %{module: AshR2RML.RedVerifierInfo.FakeDomain},
      [:resources] => %{entities: [%{resource: missing}], opts: []},
      [:r2rml_domain] => %{entities: [], opts: []}
    }

    case outcome(fn -> Verifier.verify(dsl) end) do
      {:returned, :ok} ->
        flunk("verify/1 returned :ok for an uncompiled member resource")

      {:returned, {:error, error}} ->
        refute Exception.message(error) =~ "carries no R2RML mapping"

      {:raised, _exception} ->
        :ok
    end
  end
end
