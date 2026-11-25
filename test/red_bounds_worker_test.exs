# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RedBoundsWorkerTest do
  @moduledoc """
  Red-before-green: OBDA worker concurrency/heap bounds (H38), error-boundary fidelity (H39),
  isolated bounded local SPARQL execution (H41) and `:max_rows` validation before network I/O (H42).
  """

  use ExUnit.Case, async: false

  alias AshR2RML.Error
  alias AshR2RML.Mapping.{Datatype, LogicalTable, ObjectMap, PredicateObjectMap, Resource, SubjectMap}
  alias AshR2RML.OBDA
  alias AshR2RML.OBDA.Worker
  alias AshR2RML.Refusal
  alias AshR2RML.SPARQL.{Local, Protocol}

  defmodule Boom do
    use Ash.Resource.Preparation

    @impl true
    def prepare(_query, _opts, _context), do: raise("H39-boom-marker")
  end

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.RedBoundsWorkerTest.Exploder
    end
  end

  defmodule Exploder do
    use Ash.Resource,
      domain: AshR2RML.RedBoundsWorkerTest.Domain,
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(false)
    end

    actions do
      read :read do
        primary? true
        prepare AshR2RML.RedBoundsWorkerTest.Boom
      end

      defaults(create: [:title])
    end

    identities do
      identity(:by_title, [:title], pre_check_with: AshR2RML.RedBoundsWorkerTest.Domain)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:title, :string, allow_nil?: false, public?: true)
    end
  end

  @name_pred "http://schema.org/name"
  @string "http://www.w3.org/2001/XMLSchema#string"

  defp exploder_mapping do
    %Resource{
      ash_resource: Exploder,
      logical_table: %LogicalTable{table_name: "titles"},
      subject_map: %SubjectMap{strategy: :template, value: "urn:uuid:title-{title}", term_type: :iri},
      class_iris: ["http://schema.org/Thing"],
      predicate_object_maps: [
        %PredicateObjectMap{
          attribute: :title,
          predicate_iri: @name_pred,
          object_map: %ObjectMap{
            strategy: :column,
            value: "title",
            datatype: %Datatype{ash_type: Ash.Type.String, rdf_datatype: @string}
          }
        }
      ],
      identities: [[:title]],
      metadata: %{source: :red_bounds_worker}
    }
  end

  describe "H38 worker bounds" do
    test "H38 default worker heap cap is at most 10_000_000 words" do
      assert {:ok, {:max_heap_size, %{size: size}}} =
               Worker.call(fn -> Process.info(self(), :max_heap_size) end)

      assert size <= 10_000_000
    end

    test "H38 concurrent workers are bounded below the number of callers" do
      total = 64
      test_pid = self()

      tasks =
        for _ <- 1..total do
          Task.async(fn ->
            Worker.call(
              fn ->
                send(test_pid, {:started, self()})

                receive do
                  :go -> :ok
                after
                  20_000 -> :gave_up
                end
              end,
              timeout_ms: 30_000
            )
          end)
        end

      started = drain_started(0)
      Enum.each(tasks, &Task.shutdown(&1, :brutal_kill))

      assert started < total
    end
  end

  defp drain_started(count) do
    receive do
      {:started, _pid} -> drain_started(count + 1)
    after
      400 -> count
    end
  end

  describe "H39 error boundary" do
    test "H39 a raise inside the worker keeps a stacktrace or the reason in the error" do
      result =
        OBDA.query(
          [{Exploder, exploder_mapping()}],
          "SELECT ?s ?o WHERE { ?s <#{@name_pred}> ?o }",
          domain: Domain,
          authorize?: false,
          allow_unauthorized: true
        )

      assert {:error, error} = result
      text = inspect(error, limit: :infinity, printable_limit: :infinity)

      assert text =~ "H39-boom-marker" or text =~ "stacktrace"
    end

    test "H39 wrap_failure preserves a non-struct error reason" do
      error = OBDA.wrap_failure(:error, :badarg)

      assert %Error{} = error
      assert inspect(error, limit: :infinity) =~ "badarg"
    end

    test "H39 wrap_failure preserves an exit reason" do
      error = OBDA.wrap_failure(:exit, :shutdown)

      assert %Error{} = error
      assert inspect(error, limit: :infinity) =~ "shutdown"
    end
  end

  describe "H41 local SPARQL isolation" do
    test "H41 a cartesian-product query is refused typed instead of killing the caller" do
      graph =
        RDF.Graph.new(
          for i <- 1..2000 do
            {RDF.iri("http://schema.org/s#{i}"), RDF.iri(@name_pred), RDF.literal("v#{i}")}
          end
        )

      query = "SELECT * WHERE { ?a ?p ?o . ?b ?q ?r }"
      parent = self()

      {pid, mref} =
        :erlang.spawn_opt(
          fn -> send(parent, {:outcome, safe_local(graph, query)}) end,
          [:monitor, max_heap_size: %{size: 5_000_000, kill: true, error_logger: false}]
        )

      outcome =
        receive do
          {:outcome, value} -> value
          {:DOWN, ^mref, :process, ^pid, reason} -> {:caller_died, reason}
        after
          60_000 -> :deadline
        end

      assert {:error, %Refusal{}} = outcome
    end
  end

  defp safe_local(graph, query) do
    Local.query(graph, query, max_rows: 1_000)
  catch
    kind, reason -> {:escaped, kind, reason}
  end

  describe "H42 protocol max_rows validation" do
    test "H42 invalid max_rows is refused before any connection is made" do
      {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
      {:ok, port} = :inet.port(listener)
      endpoint = "http://127.0.0.1:#{port}/sparql"

      on_exit(fn -> :gen_tcp.close(listener) end)

      for bad <- [0, :infinity, -1] do
        result =
          Protocol.query(endpoint, "SELECT * WHERE { ?s ?p ?o }",
            allow_private_network: true,
            timeout: 500,
            max_rows: bad
          )

        assert {:error, _} = result
        assert {:error, :timeout} == :gen_tcp.accept(listener, 0), "max_rows #{inspect(bad)} caused I/O"
      end
    end
  end
end
