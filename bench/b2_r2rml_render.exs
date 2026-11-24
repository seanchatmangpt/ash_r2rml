# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# B2: AshR2RML.R2RML.render/1 over 10/50/100 generated mapped resources.
#
# Run: mix run bench/b2_r2rml_render.exs
#
# Laws (exit 1 on violation):
#   * 100 resources render in <= 50 ms (min of rounds, warm)
#   * every shuffled render order is byte-identical (SHA-256)
#   * bytes allocated is reported (process heap growth in an isolated process
#     with a large pre-sized heap so no GC intervenes; binaries counted by size)

defmodule B2.Gen do
  @moduledoc false

  defmodule Dom do
    @moduledoc false
    use Ash.Domain, validate_config_inclusion?: false
  end

  @doc "Defines `n` mapped resources dynamically; returns their modules in index order."
  @spec define(pos_integer()) :: [module()]
  def define(n) do
    for i <- 1..n do
      mod = Module.concat([B2.Gen, "Res#{n}_#{i}"])

      unless Code.ensure_loaded?(mod) do
        body =
          quote do
            use Ash.Resource,
              domain: B2.Gen.Dom,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshR2RML]

            ets do
              private? true
            end

            r2rml do
              class_iri("https://example.org/b2/Class#{unquote(i)}")
              subject_template("https://example.org/b2/res#{unquote(i)}/{id}")
              table_name("b2_res_#{unquote(i)}")

              attribute_mappings([
                {:name, "https://example.org/b2/name#{unquote(i)}"},
                {:note, "https://example.org/b2/note#{unquote(i)}"}
              ])
            end

            actions do
              defaults [:read]
            end

            attributes do
              uuid_primary_key :id
              attribute :name, :string, public?: true
              attribute :note, :string, public?: true
            end
          end

        {:module, ^mod, _, _} = Module.create(mod, body, Macro.Env.location(__ENV__))
      end

      mod
    end
  end
end

defmodule B2.Run do
  @moduledoc false

  @sizes [10, 50, 100]
  @orders 5
  @rounds 7
  @budget_us 50_000

  def main do
    :rand.seed(:exsss, {20_261_124, 2, 2})

    results =
      for n <- @sizes do
        mods = B2.Gen.define(n)
        report(n, mods)
      end

    failures = Enum.flat_map(results, & &1.failures)

    if failures == [] do
      IO.puts("B2 PASS")
    else
      Enum.each(failures, &IO.puts(:stderr, "B2 FAIL: #{&1}"))
      System.halt(1)
    end
  end

  defp render!(mods) do
    case AshR2RML.R2RML.render(mods) do
      {:ok, ttl} -> ttl
      other -> raise "render refused: #{inspect(other)}"
    end
  end

  defp sha(bin), do: :crypto.hash(:sha256, bin) |> Base.encode16(case: :lower)

  defp report(n, mods) do
    orders = [mods, Enum.reverse(mods)] ++ for _ <- 1..@orders, do: Enum.shuffle(mods)

    # warm-up (also fills any lazy caches) then hash every order
    hashes = orders |> Enum.map(&(&1 |> render!() |> sha())) |> Enum.uniq()

    best_us =
      1..@rounds
      |> Enum.map(fn _ ->
        order = Enum.shuffle(mods)
        {us, _} = :timer.tc(fn -> render!(order) end)
        us
      end)
      |> Enum.min()

    {alloc_bytes, gc_free?} = allocated_bytes(Enum.shuffle(mods))
    bytes = byte_size(render!(mods))

    IO.puts(
      "B2 n=#{n} best_ms=#{Float.round(best_us / 1000, 3)} " <>
        "ttl_bytes=#{bytes} alloc_bytes=#{alloc_bytes}#{if gc_free?, do: "", else: "(gc-ran,lower-bound)"} " <>
        "distinct_sha256=#{length(hashes)} sha256=#{hd(hashes)}"
    )

    failures =
      [
        length(hashes) != 1 && "n=#{n}: #{length(hashes)} distinct renders across shuffled orders",
        n == 100 && best_us > @budget_us &&
          "n=100: best #{best_us}us exceeds #{@budget_us}us budget"
      ]
      |> Enum.filter(& &1)

    %{failures: failures}
  end

  # Runs render in an isolated process whose heap is pre-sized so no GC runs;
  # heap growth + refc-binary bytes approximate bytes allocated.
  defp allocated_bytes(order) do
    parent = self()
    word = :erlang.system_info(:wordsize)

    {pid, ref} =
      :erlang.spawn_opt(
        fn ->
          :erlang.garbage_collect()
          {:garbage_collection, gc0} = :erlang.process_info(self(), :garbage_collection)
          {:total_heap_size, h0} = :erlang.process_info(self(), :total_heap_size)
          {:memory, m0} = :erlang.process_info(self(), :memory)
          ttl = render!(order)
          {:garbage_collection, gc1} = :erlang.process_info(self(), :garbage_collection)
          {:memory, m1} = :erlang.process_info(self(), :memory)
          {:total_heap_size, h1} = :erlang.process_info(self(), :total_heap_size)

          send(
            parent,
            {:alloc, max(m1 - m0, (h1 - h0) * word) + byte_size(ttl),
             gc0[:minor_gcs] == gc1[:minor_gcs]}
          )
        end,
        [:monitor, min_heap_size: 20_000_000]
      )

    receive do
      {:alloc, bytes, gc_free?} ->
        receive do
          {:DOWN, ^ref, :process, ^pid, _} -> {bytes, gc_free?}
        end

      {:DOWN, ^ref, :process, ^pid, reason} ->
        raise "alloc probe died: #{inspect(reason)}"
    end
  end
end

B2.Run.main()
