# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# AshR2RML mapping-compilation and R2RML-rendering benchmark.
#
# Follows bench/README.md's contract: named engine (this codebase only -- no external
# database or graph engine is exercised here), correctness verified before timing, exact
# commit/versions printed with results.
#
#   MIX_ENV=test mix run bench/compilation_and_rendering.exs
#   BENCH_TIERS=10,100,1000 MIX_ENV=test mix run bench/compilation_and_rendering.exs

defmodule AshR2RML.Bench.CompilationAndRendering do
  @moduledoc false

  @xsd_string "http://www.w3.org/2001/XMLSchema#string"
  @xsd_decimal "http://www.w3.org/2001/XMLSchema#decimal"

  # A connected resource graph (each resource belongs_to the previous one), per
  # bench/README.md's "representative scale tiers" guidance -- not isolated scalar resources.
  def profile(resource_count) do
    resources =
      for i <- 0..(resource_count - 1) do
        %{
          iri: "https://bench.example/resource/R#{i}",
          class_iri: "https://bench.example/ontology/R#{i}",
          shape_iri: "https://bench.example/shapes/R#{i}Shape",
          module: "Bench.R#{i}",
          repo_module: "Bench.Repo",
          table: "bench_r#{i}",
          subject_template: "https://bench.example/id/r#{i}/{id}",
          identities: [%{name: :primary, keys: [:id], primary?: true}],
          attributes:
            [
              %{
                name: :id,
                column: "id",
                predicate_iri: "https://bench.example/ontology/id",
                datatype_iri: @xsd_string,
                ash_type: :uuid,
                postgres_type: "UUID",
                min_count: 1,
                max_count: 1,
                nullable: false,
                identity?: true
              }
            ] ++
              if i > 0 do
                [
                  %{
                    name: :parent_id,
                    predicate_iri: "https://bench.example/ontology/R#{i}/parentId",
                    datatype_iri: @xsd_string,
                    ash_type: :uuid,
                    postgres_type: "UUID",
                    min_count: 0,
                    max_count: 1
                  }
                ]
              else
                []
              end ++
              for j <- 1..8 do
                %{
                  name: :"attr_#{j}",
                  predicate_iri: "https://bench.example/ontology/R#{i}/attr#{j}",
                  datatype_iri: if(rem(j, 2) == 0, do: @xsd_decimal, else: @xsd_string),
                  min_count: 0,
                  max_count: 1
                }
              end,
          relationships:
            if i > 0 do
              [
                %{
                  name: :parent,
                  predicate_iri: "https://bench.example/ontology/hasParent",
                  source_class: "https://bench.example/ontology/R#{i}",
                  target_class: "https://bench.example/ontology/R#{i - 1}",
                  min_count: 0,
                  max_count: 1,
                  storage_strategy: :foreign_key,
                  source_key: :parent_id,
                  destination_key: :id
                }
              ]
            else
              []
            end
        }
      end

    %{
      ontology_hash: "ontology:sha256:bench-#{resource_count}",
      profile_hash: "profile:sha256:bench-#{resource_count}",
      shacl_hash: "shacl:sha256:bench-#{resource_count}",
      resources: resources
    }
  end

  def verify_correctness!(resource_count) do
    profile = profile(resource_count)

    case AshR2RML.Compiler.compile(profile) do
      {:ok, compilation} ->
        true = compilation.status == :PARTIAL_ALIVE
        true = length(compilation.mapping_bundle.resources) == resource_count
        true = String.contains?(compilation.r2rml, "rr:class <https://bench.example/ontology/R0>")
        true = is_binary(compilation.postgres_ddl)
        :ok

      {:error, compilation_or_refusal} ->
        raise "correctness verification failed for tier #{resource_count}: #{inspect(compilation_or_refusal)}"
    end
  end
end

alias AshR2RML.Bench.CompilationAndRendering, as: B

tiers =
  case System.get_env("BENCH_TIERS") do
    nil -> [10, 100, 1000]
    csv -> csv |> String.split(",") |> Enum.map(&String.to_integer/1)
  end

IO.puts("== Correctness verification (required before timing, per bench/README.md) ==")
Enum.each(tiers, fn n -> :ok = B.verify_correctness!(n) end)
IO.puts("All #{length(tiers)} tiers verified correct.\n")

jobs =
  Map.new(tiers, fn n ->
    profile = B.profile(n)

    {"compile #{n} resources (Admission→IR→Mapping→Ash+Ecto+SQL+R2RML+SHACL)",
     fn -> AshR2RML.Compiler.compile(profile) end}
  end)

Benchee.run(
  jobs,
  time: 5,
  warmup: 2,
  memory_time: 2,
  print: [configuration: false]
)
