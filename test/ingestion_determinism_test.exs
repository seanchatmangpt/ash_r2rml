# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.IngestionDeterminismTest do
  @moduledoc """
  L11: the bundle is a pure function of the canonicalised profile. Blank-node labels assigned by
  the RDF parser must never reach a hash, the IR, or any projection.
  """
  use ExUnit.Case, async: false

  alias AshR2RML.{Ggen, Ingestion}

  @fixture Path.expand("fixtures/natfac_slice1.profile.ttl", __DIR__)
  @project Path.expand("..", __DIR__)

  setup_all do
    {:ok, turtle: File.read!(@fixture)}
  end

  defp bundle_files(turtle, opts) do
    assert {:ok, bundle} = Ggen.compile_turtle_bundle(turtle, opts)
    bundle.files
  end

  defp diff_paths(a, b) do
    for path <- Enum.uniq(Map.keys(a) ++ Map.keys(b)), Map.get(a, path) != Map.get(b, path), do: path
  end

  # Same statements, shuffled order, fresh parser labels: serialise each triple on its own line.
  defp shuffled_turtle(turtle, seed) do
    {:ok, graph} = RDF.Turtle.read_string(turtle)
    :rand.seed(:exsss, {seed, seed + 1, seed + 2})

    lines =
      graph
      |> RDF.Data.statements()
      |> Enum.map(&RDF.NTriples.write_string!(RDF.Graph.new([&1])))
      |> Enum.shuffle()

    # Relabel blank nodes so the second document cannot share labels with the first.
    Enum.join(lines, "") |> String.replace("_:", "_:z#{seed}x")
  end

  for layout <- [:single, :per_resource] do
    test "two independent OS processes produce byte-identical files (#{layout})" do
      out = fn n ->
        path = Path.join(System.tmp_dir!(), "ash_r2rml_det_#{System.unique_integer([:positive])}_#{n}.bin")
        on_exit(fn -> File.rm(path) end)
        path
      end

      # The child gets the parent's exact code paths (no mix, no compile, no deps check) and writes
      # its payload to a file named by env; stdout/stderr carry only diagnostics.
      code = """
      Logger.configure(level: :error)
      {:ok, _} = Application.ensure_all_started(:ash_r2rml)
      path = System.fetch_env!("AR_DET_OUT")
      turtle = File.read!(System.fetch_env!("AR_DET_IN"))
      {:ok, b} = AshR2RML.Ggen.compile_turtle_bundle(turtle, files: String.to_atom(System.fetch_env!("AR_DET_LAYOUT")))
      File.write!(path, :erlang.term_to_binary(b.files, [:deterministic]))
      """

      run = fn path ->
        pa = Enum.flat_map(:code.get_path(), &["-pa", to_string(&1)])

        {output, status} =
          System.cmd(System.find_executable("elixir"), pa ++ ["--erl", "-kernel logger_level error", "-e", code],
            cd: @project,
            env: [
              {"AR_DET_OUT", path},
              {"AR_DET_IN", @fixture},
              {"AR_DET_LAYOUT", Atom.to_string(unquote(layout))}
            ],
            stderr_to_stdout: true
          )

        assert status == 0, "child exited #{status}:\n" <> output
        assert File.exists?(path), "child wrote no payload:\n" <> output
        path |> File.read!() |> :erlang.binary_to_term()
      end

      a = run.(out.(1))
      b = run.(out.(2))
      assert diff_paths(a, b) == []
      assert a == b

      if unquote(layout) == :per_resource do
        assert map_size(a) > 10
      else
        assert map_size(a) >= 5
      end
    end

    test "shuffled statement order and fresh bnode labels give an identical bundle (#{layout})", %{turtle: turtle} do
      baseline = bundle_files(turtle, files: unquote(layout))

      for seed <- [1, 2, 3] do
        shuffled = shuffled_turtle(turtle, seed)
        refute shuffled == turtle
        assert diff_paths(baseline, bundle_files(shuffled, files: unquote(layout))) == []
      end
    end
  end

  test "no parser-assigned blank-node label survives into any file", %{turtle: turtle} do
    files = bundle_files(turtle, files: :per_resource)

    for {path, text} <- files do
      refute text =~ ~r/"_:b\d|"_:[A-Za-z]+\d+["_]/, "blank-node label leaked into #{path}"
    end

    assert files["generated/catalog/resource-map.json"] =~ ~r/"property_shape": "_:c[0-9a-f]{64}"/
  end

  test "profile_hash is a pure function of content: literal change flips it, order does not", %{turtle: turtle} do
    {:ok, base} = Ingestion.from_turtle(turtle)
    {:ok, shuffled} = Ingestion.from_turtle(shuffled_turtle(turtle, 7))
    assert base.profile_hash == shuffled.profile_hash
    assert base.shacl_hash == shuffled.shacl_hash

    changed = String.replace(turtle, ~s(r2ml:tableName "trades"), ~s(r2ml:tableName "trades_v2"), global: false)
    refute changed == turtle
    {:ok, other} = Ingestion.from_turtle(changed)
    refute other.profile_hash == base.profile_hash
    refute other.shacl_hash == base.shacl_hash

    enum_changed = String.replace(turtle, ~s("national" "regional" "local"), ~s("national" "regional"), global: false)
    {:ok, other2} = Ingestion.from_turtle(enum_changed)
    refute other2.profile_hash == base.profile_hash
  end

  test "explicit hash options are still honoured", %{turtle: turtle} do
    {:ok, profile} = Ingestion.from_turtle(turtle, shacl_hash: "shacl:given", ontology_hash: "onto:given")
    assert profile.shacl_hash == "shacl:given"
    assert profile.ontology_hash == "onto:given"
  end
end
