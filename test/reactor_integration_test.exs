# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.TestReactorWorkflow do
  use Reactor

  input(:resources)

  step :compile_r2rml, AshR2RML.Reactor.CompileR2RML do
    argument :resources, input(:resources)
  end
end

defmodule AshR2RML.ReactorIntegrationTest do
  use ExUnit.Case, async: true

  test "executes AshR2RML compilation natively inside a Reactor workflow saga" do
    profile = %{
      class: "https://schema.org/Person",
      subject: %{template: "https://example.org/users/{id}"},
      attributes: [
        %{name: :id, type: :string, primary_key?: true},
        %{name: :name, type: :string, predicate: "http://xmlns.com/foaf/0.1/name"}
      ]
    }

    assert {:ok, %AshR2RML.Compilation{} = compilation} =
             Reactor.run(AshR2RML.TestReactorWorkflow, %{resources: profile})

    assert compilation.status == :PARTIAL_ALIVE
    assert is_binary(compilation.ash_source)
  end
end
