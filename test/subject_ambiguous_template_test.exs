# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.SubjectAmbiguousTemplateTest do
  @moduledoc """
  Templates whose separator between two placeholders is made only of characters that can occur
  inside a percent-encoded value (URI unreserved or `%`) invert ambiguously by first-match split
  (`{a}-{b}` with a="x-y", b="z"), yet the roundtrip check passes. `from_iri/2` must refuse.
  """

  use ExUnit.Case, async: true

  alias AshR2RML.Mapping.{LogicalTable, Resource, SubjectMap}
  alias AshR2RML.{Refusal, Subject}

  defp mapping(template) do
    %Resource{
      ash_resource: "Thing",
      logical_table: %LogicalTable{table_name: "things"},
      subject_map: %SubjectMap{strategy: :template, value: template}
    }
  end

  test "to_iri still renders the ambiguous template (forward direction is total)" do
    assert {:ok, "http://ex/p/x-y-z"} = Subject.to_iri(mapping("http://ex/p/{a}-{b}"), %{a: "x-y", b: "z"})
  end

  for sep <- ["-", ".", "_", "~", "ab", "-.-", "%"] do
    test "from_iri refuses unreserved-only separator #{inspect(sep)}" do
      template = "http://ex/p/{a}#{unquote(sep)}{b}"
      assert {:ok, iri} = Subject.to_iri(mapping(template), %{a: "x", b: "z"})

      assert {:error, %Refusal{code: :REFUSED_NON_INVERTIBLE_TEMPLATE}} = Subject.from_iri(mapping(template), iri)
    end
  end

  test "from_iri refuses the witnessed ambiguous IRI instead of mis-splitting" do
    m = mapping("http://ex/p/{a}-{b}")
    assert {:error, %Refusal{code: :REFUSED_NON_INVERTIBLE_TEMPLATE}} = Subject.from_iri(m, "http://ex/p/x-y-z")
  end

  test "reserved-character separators stay invertible (positive control)" do
    m = mapping("http://ex/p/{a}/{b}")
    assert {:ok, %{a: "x-y", b: "z"}} = Subject.from_iri(m, "http://ex/p/x-y/z")

    m2 = mapping("http://ex/orgs/{a}/people/{b}")
    assert {:ok, %{a: "o", b: "p"}} = Subject.from_iri(m2, "http://ex/orgs/o/people/p")
  end

  test "to_iri refuses an empty value with no Ash attribute so it agrees with from_iri" do
    m = mapping("http://ex/p/{a}")
    assert {:error, %Refusal{code: :REFUSED_INVALID_SUBJECT_IRI}} = Subject.to_iri(m, %{a: ""})
    assert {:error, %Refusal{}} = Subject.from_iri(m, "http://ex/p/")
  end
end
