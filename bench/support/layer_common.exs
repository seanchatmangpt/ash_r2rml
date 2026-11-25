# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Pure helpers shared by every bench/stress/layers/<layer>.exs module. No layer knowledge, no
# data-layer references. Contract summary lives in the lane charter; this file only supplies
# refusal extraction, the shared healthy fixture (mapping + SPARQL + seeding), a canonical
# layer-independent digest, leak snapshots and a monotonic-deadline poll.

defmodule Bench.Layer.Common do
  @moduledoc """
  Shared helpers for stress layer modules (`Bench.Layer.<Camel>`).

  * `code_of/1`, `expect_refusal/2`, `healthy?/1` -- typed refusal handling.
  * `shared_sparql/0`, `shared_mapping/2`, `seed_people/5` -- the healthy Person fixture.
  * `digest_of/1` -- digest over canonical bindings only, so it is identical across layers
    (the envelope digest also covers rendered Turtle, which names the resource module).
  * `snapshot/0`, `assert_no_leak/3` -- atom/ets/process/port deltas.
  * `poll/3` -- bounded poll on a monotonic deadline.
  """

  alias AshR2RML.Error
  alias AshR2RML.Mapping.{Datatype, LogicalTable, ObjectMap, PredicateObjectMap, Resource, SubjectMap}
  alias AshR2RML.OBDA.Result
  alias AshR2RML.Refusal

  @ex "https://ex.org/"
  @xsd "http://www.w3.org/2001/XMLSchema#"
  @name_iri "https://schema.org/name"
  @age_iri "https://schema.org/age"

  @sparql "SELECT ?s ?n ?a WHERE { ?s <https://schema.org/name> ?n ; <https://schema.org/age> ?a }"

  @refusal_codes [
    :REFUSED_RESULT_LIMIT_EXCEEDED,
    :REFUSED_TRIPLE_LIMIT_EXCEEDED,
    :REFUSED_MEMORY_LIMIT_EXCEEDED,
    :REFUSED_QUERY_TIMEOUT
  ]

  @doc "The four killer-scenario refusal codes."
  @spec refusal_codes() :: [atom()]
  def refusal_codes, do: @refusal_codes

  # ---------------------------------------------------------------- refusals

  @doc """
  Extracts the refusal code atom from `{:error, %Refusal{} | %Error{} | [refusal | error]}`
  (or the bare struct / list). Returns `nil` when the value carries no typed code.
  """
  @spec code_of(term()) :: atom() | nil
  def code_of({:error, reason}), do: code_of(reason)
  def code_of(%Refusal{code: code}), do: code
  def code_of(%Error{code: code}), do: code
  def code_of([first | _]), do: code_of(first)
  def code_of(_), do: nil

  @doc "`:ok` when `result` is refused with `code`, else `{:fail, why}`."
  @spec expect_refusal(term(), atom()) :: :ok | {:fail, term()}
  def expect_refusal(result, code) when is_atom(code) do
    case code_of(result) do
      ^code -> :ok
      nil -> {:fail, {:expected_refusal, code, :got, summarize(result)}}
      other -> {:fail, {:expected_refusal, code, :got_code, other}}
    end
  end

  @doc "True for `{:ok, %AshR2RML.OBDA.Result{}}` (or the bare struct)."
  @spec healthy?(term()) :: boolean()
  def healthy?({:ok, %Result{}}), do: true
  def healthy?(%Result{}), do: true
  def healthy?(_), do: false

  # ---------------------------------------------------------------- shared fixture

  @doc "The shared healthy SPARQL query text."
  @spec shared_sparql() :: String.t()
  def shared_sparql, do: @sparql

  @doc """
  Person `AshR2RML.Mapping.Resource` for any resource module with attributes
  `pid`, `name`, `age`.

  Options: `:table` (logical table name, default `"person"`).
  """
  @spec shared_mapping(module(), keyword()) :: Resource.t()
  def shared_mapping(resource, opts \\ []) when is_atom(resource) do
    %Resource{
      ash_resource: resource,
      logical_table: %LogicalTable{table_name: Keyword.get(opts, :table, "person")},
      subject_map: %SubjectMap{strategy: :template, value: @ex <> "person/{pid}"},
      class_iris: [@ex <> "Person"],
      identities: [[:pid]],
      predicate_object_maps: [
        %PredicateObjectMap{
          attribute: :name,
          predicate_iri: @name_iri,
          object_map: %ObjectMap{
            strategy: :column,
            value: "name",
            datatype: %Datatype{ash_type: :string, rdf_datatype: @xsd <> "string"}
          }
        },
        %PredicateObjectMap{
          attribute: :age,
          predicate_iri: @age_iri,
          object_map: %ObjectMap{
            strategy: :column,
            value: "age",
            datatype: %Datatype{ash_type: :integer, rdf_datatype: @xsd <> "integer"}
          }
        }
      ]
    }
  end

  @doc """
  Canonical digest of a query result: SHA-256 (lowercase hex) over the canonically sorted
  bindings/triples only. Layer-independent for identical seed data, unlike `Result.digest`
  which also hashes rendered Turtle (module-name bearing).
  """
  @spec digest_of({:ok, Result.t()} | Result.t()) :: binary()
  def digest_of({:ok, %Result{} = r}), do: digest_of(r)

  def digest_of(%Result{bindings: bindings, triples: triples, kind: kind}) do
    canonical =
      :erlang.term_to_binary(
        {kind, Result.canonical_sort(bindings), Result.canonical_sort(triples)},
        [:deterministic]
      )

    :crypto.hash(:sha256, canonical) |> Base.encode16(case: :lower)
  end

  @doc "Envelope digest (`Result.digest`) of a result, for same-layer determinism checks."
  @spec envelope_digest({:ok, Result.t()} | Result.t()) :: binary()
  def envelope_digest({:ok, %Result{digest: d}}), do: d
  def envelope_digest(%Result{digest: d}), do: d

  @doc """
  Seeds Person rows `pid "p1".."pN"`, name `"Person i"`, age `i` through `Ash.bulk_create`.

  `extra_attrs_fun` is `(i -> map)` merged over each input (tenant column, org id, ...).
  Options: `:action` (default `:create`), `:batch_size` (default 500), plus `:tenant`,
  `:actor`, `:authorize?` (default `false`) forwarded to Ash. Returns `:ok` or
  `{:error, errors}`.
  """
  @spec seed_people(module(), module(), non_neg_integer(), (pos_integer() -> map()), keyword()) ::
          :ok | {:error, term()}
  def seed_people(resource, domain, n, extra_attrs_fun \\ fn _ -> %{} end, opts \\ [])
      when is_integer(n) and n >= 0 and is_function(extra_attrs_fun, 1) do
    inputs =
      for i <- 1..n//1 do
        Map.merge(%{pid: "p#{i}", name: "Person #{i}", age: i}, extra_attrs_fun.(i))
      end

    ash_opts =
      [
        domain: domain,
        batch_size: Keyword.get(opts, :batch_size, 500),
        authorize?: Keyword.get(opts, :authorize?, false),
        return_errors?: true,
        stop_on_error?: true
      ] ++ Keyword.take(opts, [:tenant, :actor])

    case inputs do
      [] ->
        :ok

      _ ->
        case Ash.bulk_create(inputs, resource, Keyword.get(opts, :action, :create), ash_opts) do
          %Ash.BulkResult{status: :success} -> :ok
          %Ash.BulkResult{errors: errors} -> {:error, errors}
          other -> {:error, other}
        end
    end
  end

  # ---------------------------------------------------------------- leak snapshots

  @type snapshot :: %{
          atoms: non_neg_integer(),
          ets: non_neg_integer(),
          processes: non_neg_integer(),
          ports: non_neg_integer()
        }

  @doc "Counts of atoms, ETS tables, processes and ports (fd proxy: `:port_count`)."
  @spec snapshot() :: snapshot()
  def snapshot do
    %{
      atoms: :erlang.system_info(:atom_count),
      ets: length(:ets.all()),
      processes: :erlang.system_info(:process_count),
      ports: :erlang.system_info(:port_count)
    }
  end

  @doc """
  Compares two snapshots. Returns `:ok` or `{:fail, {:leak, %{key => delta}}}` for every key
  whose growth exceeds its tolerance. Tolerances (opts, all non-negative integers):
  `:atoms` (default 512, lazy module loading mints atoms), `:ets` (0), `:processes` (0),
  `:ports` (0).
  """
  @spec assert_no_leak(snapshot(), snapshot(), keyword()) :: :ok | {:fail, term()}
  def assert_no_leak(before, after_, opts \\ []) do
    tol = %{
      atoms: Keyword.get(opts, :atoms, 512),
      ets: Keyword.get(opts, :ets, 0),
      processes: Keyword.get(opts, :processes, 0),
      ports: Keyword.get(opts, :ports, 0)
    }

    breaches =
      for {key, limit} <- tol, (delta = Map.fetch!(after_, key) - Map.fetch!(before, key)) > limit,
          into: %{},
          do: {key, delta}

    if breaches == %{}, do: :ok, else: {:fail, {:leak, breaches}}
  end

  @doc """
  Runs `fun`, then polls (bounded by `settle_ms`) until the snapshot taken afterwards is
  within tolerance of the one taken before, so asynchronous teardown is observed rather than
  slept on. Returns `{result, :ok | {:fail, term}}`.
  """
  @spec with_leak_check((-> term()), keyword()) :: {term(), :ok | {:fail, term()}}
  def with_leak_check(fun, opts \\ []) when is_function(fun, 0) do
    before = snapshot()
    result = fun.()
    settle = Keyword.get(opts, :settle_ms, 2_000)

    verdict =
      case poll(fn -> assert_no_leak(before, snapshot(), opts) == :ok end, settle) do
        {:ok, _} -> :ok
        {:error, :timeout} -> assert_no_leak(before, snapshot(), opts)
      end

    {result, verdict}
  end

  # ---------------------------------------------------------------- poll

  @doc """
  Polls `fun` until it returns a truthy value or `ms` elapse on a monotonic deadline.
  Returns `{:ok, value}` or `{:error, :timeout}`. `fun` is always evaluated at least once and
  once more at the deadline. Option `step_ms` (default 5) paces re-evaluation.
  """
  @spec poll((-> term()), non_neg_integer(), keyword()) :: {:ok, term()} | {:error, :timeout}
  def poll(fun, ms, opts \\ []) when is_function(fun, 0) and is_integer(ms) and ms >= 0 do
    step = Keyword.get(opts, :step_ms, 5)
    deadline = System.monotonic_time(:millisecond) + ms
    do_poll(fun, deadline, step)
  end

  defp do_poll(fun, deadline, step) do
    case fun.() do
      falsy when falsy in [nil, false] ->
        remaining = deadline - System.monotonic_time(:millisecond)

        if remaining <= 0 do
          {:error, :timeout}
        else
          # SLEEP-CLASS: POLL-STEP (the single audited pacing point of this bounded poll)
          receive do
          after
            min(step, remaining) -> :ok
          end

          do_poll(fun, deadline, step)
        end

      value ->
        {:ok, value}
    end
  end

  defp summarize({:ok, %Result{stats: stats}}), do: {:ok_result, stats}
  defp summarize(other), do: other
end
