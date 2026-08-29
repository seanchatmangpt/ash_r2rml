# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.CompilerEtsBackendTest do
  use ExUnit.Case, async: true

  @xsd_string "http://www.w3.org/2001/XMLSchema#string"

  defp profile do
    %{
      ontology_hash: "ontology:sha256:ets-aaa",
      profile_hash: "profile:sha256:ets-bbb",
      shacl_hash: "shacl:sha256:ets-ccc",
      resources: [
        %{
          iri: "https://xaas.example/resource/Widget",
          class_iri: "https://xaas.example/ontology/Widget",
          shape_iri: "https://xaas.example/shapes/WidgetShape",
          module: "Xaas.Widget",
          repo_module: "Xaas.Repo",
          table: "widgets",
          subject_template: "https://xaas.example/id/widget/{id}",
          identities: [%{name: :primary, keys: [:id], primary?: true}],
          attributes: [
            %{
              name: :id,
              column: "id",
              predicate_iri: "https://xaas.example/ontology/id",
              datatype_iri: @xsd_string,
              ash_type: :uuid,
              postgres_type: "UUID",
              min_count: 1,
              max_count: 1,
              nullable: false,
              identity?: true
            },
            %{
              name: :name,
              predicate_iri: "http://xmlns.com/foaf/0.1/name",
              datatype_iri: @xsd_string,
              min_count: 1,
              max_count: 1
            }
          ]
        }
      ]
    }
  end

  test "storage_backend: :postgres (default) renders SQL DDL as before" do
    assert {:ok, compilation} = AshR2RML.Compiler.compile(profile())

    assert is_binary(compilation.postgres_ddl)
    assert compilation.postgres_ddl =~ "widgets"
    assert compilation.receipt.postgres_sha256 != nil
    assert :postgres_render in compilation.receipt.executed
  end

  test "storage_backend: :ets skips SQL DDL rendering without blocking the compilation" do
    assert {:ok, compilation} = AshR2RML.Compiler.compile(profile(), storage_backend: :ets)

    assert compilation.status == :PARTIAL_ALIVE
    assert compilation.standing == :constructed_not_actuated
    assert compilation.postgres_ddl == nil
    assert :postgres_ddl_skipped_ets_backend in compilation.receipt.executed
    refute :postgres_render in compilation.receipt.executed

    # Everything backend-independent still renders for real.
    assert is_binary(compilation.ash_source)
    assert is_binary(compilation.ecto_migration)
    assert compilation.r2rml =~ "rr:class <https://xaas.example/ontology/Widget>"
    assert is_binary(compilation.shacl)
    assert %AshR2RML.Mapping.Bundle{} = compilation.mapping_bundle
  end
end
