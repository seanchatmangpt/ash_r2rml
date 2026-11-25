# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RedPersistTest do
  @moduledoc """
  Persist transformer: ordering after Ash resource-building transformers and
  structured Spark.Error.DslError diagnostics on refusal.
  """
  use ExUnit.Case, async: false

  alias AshR2RML.Resource.Persist

  defp compile_error(name, r2rml_body) do
    source = """
    defmodule #{name} do
      use Ash.Resource,
        domain: nil,
        data_layer: Ash.DataLayer.Ets,
        extensions: [AshR2RML.Resource]

      r2rml do
        table_name("red_persist_things")
        class("http://schema.org/Thing")
        #{r2rml_body}
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

  test "H08 Persist runs after Ash resource-building transformers other than the five hardcoded" do
    others = [
      Ash.Resource.Transformers.SetTypes,
      Ash.Resource.Transformers.ValidateRelationshipAttributes,
      Ash.Resource.Transformers.SetPrimaryActions,
      Ash.Resource.Transformers.BelongsToAttribute
    ]

    for transformer <- others do
      assert Persist.after?(transformer) == true,
             "Persist must run after #{inspect(transformer)}"
    end
  end

  test "H09 refusal at compile time is a Spark.Error.DslError with module and r2rml path" do
    error = compile_error("AshR2RML.RedPersistTest.NoSubject", "")

    assert %Spark.Error.DslError{} = error
    assert error.module == AshR2RML.RedPersistTest.NoSubject
    assert error.path == [:r2rml]
  end

  test "H22 refusal diagnostic carries the refusal code and its evidence" do
    body = ~s|subject(template: "urn:uuid:{id}", column: :id)|
    error = compile_error("AshR2RML.RedPersistTest.TwoStrategies", body)

    assert %Spark.Error.DslError{} = error
    assert error.module == AshR2RML.RedPersistTest.TwoStrategies
    assert error.path == [:r2rml]

    message = Exception.message(error)
    assert message =~ "REFUSED_MISSING_SUBJECT_MAP"
    assert message =~ "configured"
  end
end
