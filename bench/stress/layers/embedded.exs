# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Layer `embedded`: Person parents on Ash.DataLayer.Ets carrying an embedded-resource array
# (`children`). Scenarios S1 (memory bound), S3 (triple bound), S5 (mixed storm) and
# S11 (100 parents x 500 embedded children = 50_000 nested entities).
#
# Mapping facts (lib/ash_r2rml/datatype_registry.ex): an attribute of type {:array, Embedded}
# has no admitted RDF datatype contract, so mapping it via `property/2` is REFUSED at DSL
# compile time (UNSUPPORTED_ASH_TYPE). Parent scalar attributes map normally and the embedded
# array stays unmapped but resident in every read row. S11 asserts both halves and records
# 'UNSUPPORTED: embedded array mapping'. No sub-IRIs are fabricated.

defmodule Bench.Layer.Embedded.Child do
  @moduledoc false
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :idx, :integer, public?: true
    attribute :label, :string, public?: true
  end
end

defmodule Bench.Layer.Embedded do
  @moduledoc false

  @person "https://schema.org/"
  @sparql "SELECT ?s ?n ?a WHERE { ?s <https://schema.org/name> ?n ; <https://schema.org/age> ?a }"
  @child Bench.Layer.Embedded.Child
  @storm_workers 16
  @storm_deadline_ms 120_000

  def available?, do: :ok

  def setup(opts) do
    rows = Keyword.get(opts, :rows, 10_000)
    digest_rows = Keyword.get(opts, :digest_rows, 500)

    {domain, resource} = build(false)
    seed(resource, domain, rows, 0)
    {:ok, mapping} = AshR2RML.Resource.Info.mapping_result(resource)

    {ddomain, dresource} = build(false)
    seed(dresource, ddomain, digest_rows, 0)
    {:ok, dmapping} = AshR2RML.Resource.Info.mapping_result(dresource)

    created = [resource, dresource]

    {:ok,
     %{
       specs: [{resource, mapping}],
       domain: domain,
       resource: resource,
       seed_rows: rows,
       digest_specs: [{dresource, dmapping}],
       digest_domain: ddomain,
       digest_rows: digest_rows,
       teardown: fn -> Enum.each(created, &stop/1) end
     }}
  rescue
    e -> {:skip, "embedded layer setup failed: " <> Exception.message(e)}
  end

  def scenarios do
    [
      {:s1, "embedded heap bomb: 50k nested entities under tiny max_heap_words", &s1/1},
      {:s3, "triple bound on parent graph", &s3/1},
      {:s5, "mixed killer/healthy storm over embedded parents", &s5/1},
      {:s11, "100 parents x 500 embedded children; array mapping unsupported (typed)", &s11/1}
    ]
  end

  def canonical_digest(ctx) do
    {:ok, result} =
      AshR2RML.OBDA.query(ctx.digest_specs, @sparql, domain: ctx.digest_domain, authorize?: false)

    result.digest
  end

  # -- scenarios ----------------------------------------------------------

  defp s1(_ctx) do
    {domain, resource, specs} = nested()

    try do
      outcome =
        AshR2RML.OBDA.query(specs, @sparql,
          domain: domain,
          authorize?: false,
          max_heap_words: 100_000,
          timeout_ms: 60_000
        )

      expect_code(outcome, :REFUSED_MEMORY_LIMIT_EXCEEDED, "S1")
    after
      stop(resource)
    end
  end

  defp s3(ctx) do
    outcome =
      AshR2RML.OBDA.query(ctx.specs, @sparql,
        domain: ctx.domain,
        authorize?: false,
        max_triples: 1_000,
        timeout_ms: 60_000
      )

    expect_code(outcome, :REFUSED_TRIPLE_LIMIT_EXCEEDED, "S3")
  end

  defp s5(ctx) do
    killer = fn ->
      AshR2RML.OBDA.query(ctx.digest_specs, @sparql,
        domain: ctx.digest_domain,
        authorize?: false,
        max_rows: 10
      )
    end

    healthy = fn ->
      AshR2RML.OBDA.query(ctx.digest_specs, @sparql, domain: ctx.digest_domain, authorize?: false)
    end

    jobs = for i <- 1..@storm_workers, do: if(rem(i, 2) == 0, do: {:killer, killer}, else: {:healthy, healthy})
    expected = canonical_digest(ctx)

    results =
      jobs
      |> Task.async_stream(fn {kind, f} -> {kind, f.()} end,
        max_concurrency: @storm_workers,
        timeout: @storm_deadline_ms,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, r} -> r
        {:exit, reason} -> {:crash, reason}
      end)

    bad =
      Enum.reject(results, fn
        {:killer, outcome} -> code_of(outcome) == :REFUSED_RESULT_LIMIT_EXCEEDED
        {:healthy, {:ok, %{digest: d}}} -> d == expected
        _ -> false
      end)

    if bad == [], do: :ok, else: {:fail, {:storm_breaches, length(bad), inspect(hd(bad), limit: 8)}}
  end

  defp s11(_ctx) do
    {domain, resource, specs} = nested()

    try do
      healthy =
        case AshR2RML.OBDA.query(specs, @sparql, domain: domain, authorize?: false, timeout_ms: 60_000) do
          {:ok, %{bindings: b}} when length(b) == 100 -> :ok
          {:ok, %{bindings: b}} -> {:fail, {:s11_unexpected_binding_count, length(b)}}
          other -> {:fail, {:s11_healthy_query, inspect(other, limit: 8)}}
        end

      with :ok <- healthy do
        unsupported_array_mapping()
      end
    after
      stop(resource)
    end
  end

  defp unsupported_array_mapping do
    refused? =
      try do
        {_d, r} = build(true)

        case AshR2RML.Resource.Info.mapping_result(r) do
          {:error, _} -> true
          {:ok, _} -> false
        end
      rescue
        e -> Exception.message(e) =~ ~r/datatype|UNSUPPORTED|REFUSED/i
      end

    if refused? do
      IO.puts("UNSUPPORTED: embedded array mapping (typed refusal at DSL compile, no fabricated support)")
      :ok
    else
      {:fail, :embedded_array_mapping_unexpectedly_accepted}
    end
  end

  # -- helpers ------------------------------------------------------------

  defp nested do
    {domain, resource} = build(false)
    seed(resource, domain, 100, 500)
    {:ok, mapping} = AshR2RML.Resource.Info.mapping_result(resource)
    {domain, resource, [{resource, mapping}]}
  end

  defp expect_code(outcome, code, label) do
    case code_of(outcome) do
      ^code -> :ok
      other -> {:fail, {:"#{label}_wrong_outcome", expected: code, got: other, outcome: inspect(outcome, limit: 6)}}
    end
  end

  defp code_of(outcome) do
    if Code.ensure_loaded?(Bench.Layer.Common) and function_exported?(Bench.Layer.Common, :code_of, 1) do
      Bench.Layer.Common.code_of(outcome)
    else
      case outcome do
        {:error, %{code: code}} -> code
        {:ok, _} -> :ok
        _ -> :unknown
      end
    end
  end

  defp stop(resource) do
    Ash.DataLayer.Ets.stop(resource)
    :ok
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  defp seed(_resource, _domain, 0, _children), do: :ok

  defp seed(resource, domain, n, children_per_row) do
    kids = for j <- 1..children_per_row//1, do: %{idx: j, label: "child #{j}"}

    inputs =
      for i <- 1..n do
        %{pid: "p#{i}", name: "Person #{i}", age: i, children: kids}
      end

    %Ash.BulkResult{status: :success} =
      Ash.bulk_create(inputs, resource, :create,
        domain: domain,
        authorize?: false,
        return_errors?: true,
        stop_on_error?: true
      )

    :ok
  end

  # Builds a uniquely named domain + parent resource. map_children? adds the (unsupported)
  # property mapping for the embedded array.
  defp build(map_children?) do
    n = System.unique_integer([:positive])
    domain = Module.concat([Bench.Layer.Embedded, "Domain#{n}"])
    resource = Module.concat([Bench.Layer.Embedded, "Person#{n}"])
    child = @child
    schema = @person

    extra =
      if map_children?,
        do: [quote(do: property(:children, "https://ex.org/children"))],
        else: []

    Module.create(
      domain,
      quote do
        use Ash.Domain, validate_config_inclusion?: false

        resources do
          resource unquote(resource)
        end
      end,
      Macro.Env.location(__ENV__)
    )

    Module.create(
      resource,
      quote do
        use Ash.Resource,
          domain: unquote(domain),
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshR2RML.Resource]

        actions do
          defaults [:read, create: [:pid, :name, :age, :children]]
        end

        attributes do
          attribute :pid, :string, primary_key?: true, allow_nil?: false, public?: true
          attribute :name, :string, public?: true
          attribute :age, :integer, public?: true
          attribute :children, {:array, unquote(child)}, public?: true, default: []
        end

        identities do
          identity :by_pid, [:pid]
        end

        r2rml do
          table_name("person")
          class("https://ex.org/Person")

          subject do
            template("https://ex.org/person/{pid}")
          end

          property(:name, unquote(schema <> "name"))
          property(:age, unquote(schema <> "age"))
          unquote_splicing(extra)
        end
      end,
      Macro.Env.location(__ENV__)
    )

    {domain, resource}
  end
end
