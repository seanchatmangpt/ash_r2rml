# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Red2RefusalSurfaceTest do
  @moduledoc """
  Red-before-green: the `AshR2RML.Refusal` surface. The `code` type must list every emitted
  code, `exception/1` and `raise` must stamp the class from `class_for/1`, and
  `Exception.message/1` must carry subject and evidence.
  """

  use ExUnit.Case, async: true

  alias AshR2RML.Refusal

  @emitted_codes [
    :REFUSED_UNAUTHORIZED,
    :REFUSED_QUERY_TIMEOUT,
    :REFUSED_READ_FAILED,
    :REFUSED_WORKER_CRASHED,
    :REFUSED_MEMORY_LIMIT_EXCEEDED,
    :REFUSED_MISSING_SUBJECT_KEY,
    :REFUSED_INVALID_SUBJECT_IRI,
    :REFUSED_NON_INVERTIBLE_TEMPLATE
  ]

  defp union_atoms({:atom, _, atom}), do: [atom]
  defp union_atoms({:type, _, :union, members}), do: Enum.flat_map(members, &union_atoms/1)
  defp union_atoms(_other), do: []

  defp declared_codes do
    {:ok, types} = Code.Typespec.fetch_types(Refusal)

    [ast] =
      for {kind, {:code, ast, _args}} <- types, kind in [:type, :opaque], do: ast

    union_atoms(ast)
  end

  test "code type lists every emitted refusal code" do
    declared = declared_codes()
    missing = Enum.reject(@emitted_codes, &(&1 in declared))
    assert missing == []
  end

  test "exception/1 stamps the class from class_for/1" do
    for code <- @emitted_codes do
      e = Refusal.exception(code: code, subject: :s, detail: "d")
      assert e.class == Refusal.class_for(code)
    end

    forbidden = Refusal.exception(code: :REFUSED_UNAUTHORIZED, subject: :s, detail: "d")
    assert forbidden.class == :forbidden
  end

  test "raise stamps the class from class_for/1" do
    e =
      try do
        raise Refusal, code: :REFUSED_UNAUTHORIZED, subject: :s, detail: "d"
      rescue
        err in Refusal -> err
      end

    assert e.class == :forbidden

    e2 =
      try do
        raise Refusal, code: :REFUSED_QUERY_TIMEOUT, subject: :s, detail: "d"
      rescue
        err in Refusal -> err
      end

    assert e2.class == :unknown
  end

  test "Exception.message/1 includes subject and evidence" do
    r =
      Refusal.new(
        :REFUSED_MISSING_SUBJECT_KEY,
        :red2_subject_marker,
        "subject key absent",
        %{red2_key: :red2_evidence_marker}
      )

    msg = Exception.message(r)
    assert msg =~ "REFUSED_MISSING_SUBJECT_KEY"
    assert msg =~ "red2_subject_marker"
    assert msg =~ "red2_evidence_marker"
  end
end
