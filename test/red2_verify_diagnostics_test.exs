# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Red2VerifyDiagnosticsTest do
  @moduledoc """
  Compile-time diagnostics must name every offending attribute/relationship,
  not just the first refusal, and must not drop the refusal subject.
  """
  use ExUnit.Case, async: false

  alias AshR2RML.Mapping.{Bundle, Resource, SubjectMap}
  alias AshR2RML.R2RML.Terms

  defp compile_error(name, body) do
    source = """
    defmodule #{name} do
      use Ash.Resource,
        domain: nil,
        data_layer: Ash.DataLayer.Ets,
        extensions: [AshR2RML.Resource]

      r2rml do
        table_name("red2_diag_things")
        class("http://schema.org/Thing")
        subject(template: "urn:uuid:{id}")
        #{body}
      end

      actions do
        defaults [:read]
      end

      attributes do
        uuid_primary_key :id
      end
    end
    """

    try do
      Code.compile_string(source)
      :compiled
    rescue
      error -> error
    end
  end

  test "single unknown attribute is named in the message" do
    body = ~s|property(:ghost_alpha, "http://schema.org/name")|
    error = compile_error("AshR2RML.Red2Diag.OneAttr", body)

    assert %Spark.Error.DslError{} = error
    assert Exception.message(error) =~ "ghost_alpha"
  end

  test "two unknown attributes are both named" do
    body = """
    property(:ghost_alpha, "http://schema.org/name")
    property(:ghost_beta, "http://schema.org/alternateName")
    """

    error = compile_error("AshR2RML.Red2Diag.TwoAttrs", body)

    assert %Spark.Error.DslError{} = error
    message = Exception.message(error)
    assert message =~ "ghost_alpha"
    assert message =~ "ghost_beta"
  end

  test "unknown attribute and unknown relationship are both named" do
    body = """
    property(:ghost_alpha, "http://schema.org/name")
    reference(:ghost_rel, "http://schema.org/isRelatedTo")
    """

    error = compile_error("AshR2RML.Red2Diag.AttrAndRel", body)

    assert %Spark.Error.DslError{} = error
    message = Exception.message(error)
    assert message =~ "ghost_alpha"
    assert message =~ "ghost_rel"
  end

  test "two unknown relationships are both named" do
    body = """
    reference(:ghost_rel_one, "http://schema.org/isRelatedTo")
    reference(:ghost_rel_two, "http://schema.org/relatedLink")
    """

    error = compile_error("AshR2RML.Red2Diag.TwoRels", body)

    assert %Spark.Error.DslError{} = error
    message = Exception.message(error)
    assert message =~ "ghost_rel_one"
    assert message =~ "ghost_rel_two"
  end

  test "diagnostic path points below [:r2rml] at the offending attribute" do
    body = ~s|property(:ghost_alpha, "http://schema.org/name")|
    error = compile_error("AshR2RML.Red2Diag.PathAttr", body)

    assert %Spark.Error.DslError{} = error
    assert hd(error.path) == :r2rml
    assert :ghost_alpha in error.path
  end

  defp bad_resource(name, bad_class) do
    %Resource{
      ash_resource: name,
      logical_table: %AshR2RML.Mapping.LogicalTable{table_name: "t"},
      subject_map: %SubjectMap{strategy: :template, value: "urn:uuid:x-{id}"},
      class_iris: [bad_class]
    }
  end

  test "Terms.validate surfaces every refusal across the bundle, not only the first" do
    bundle = %Bundle{
      resources: [
        bad_resource(Red2.First, "http://schema.org/bad one"),
        bad_resource(Red2.Second, "http://schema.org/bad two")
      ]
    }

    assert {:error, refusal} = Terms.validate(bundle)
    shown = inspect(refusal, limit: :infinity, printable_limit: :infinity)
    assert shown =~ "bad one"
    assert shown =~ "bad two"
  end
end
