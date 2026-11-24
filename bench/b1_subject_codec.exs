# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# B1: AshR2RML.Subject codec latency.
#
# Run with: MIX_ENV=test mix run bench/b1_subject_codec.exs
#
# Measures one to_iri/2 + from_iri/2 round trip per key over 10_000 keys spread across
# uuid, integer, decimal, date, NewType and composite (percent-encoded) key templates.
# Gate: p99 <= 50us and one-sided Cpk (USL = 50us) >= 1.67. Exit via Stats.exit_with/1.
#
# Requires bench/support/stats.exs to define `Stats` (functions used here:
# `Stats.exit_with(checks)` where checks is a list of `{name, pass?, detail_map}`).

Code.require_file("support/stats.exs", __DIR__)

defmodule B1.Code do
  use Ash.Type.NewType, subtype_of: :string
end

defmodule B1.Dom do
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource B1.Thing
  end
end

defmodule B1.Thing do
  use Ash.Resource, domain: B1.Dom, data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  actions do
    defaults [:read]
  end

  attributes do
    uuid_primary_key :id
    attribute :n, :integer, public?: true
    attribute :amt, :decimal, public?: true
    attribute :day, :date, public?: true
    attribute :code, B1.Code, public?: true
    attribute :org, :string, public?: true
    attribute :pid, :string, public?: true
  end
end

defmodule B1.Run do
  alias AshR2RML.Mapping.{LogicalTable, Resource, SubjectMap}

  @ex "http://ex.org/"
  @keys 10_000
  @usl_us 50.0
  @p99_max_us 50.0
  @cpk_min 1.67

  def mapping(template) do
    %Resource{
      ash_resource: B1.Thing,
      logical_table: %LogicalTable{table_name: "things"},
      subject_map: %SubjectMap{strategy: :template, value: @ex <> template}
    }
  end

  def cases do
    [
      {:uuid, mapping("u/{id}"), fn i -> %{id: uuid(i)} end},
      {:integer, mapping("n/{n}"), fn i -> %{n: i} end},
      {:decimal, mapping("d/{amt}"), fn i -> %{amt: Decimal.new("#{i}.#{rem(i, 100) + 10}")} end},
      {:date, mapping("t/{day}"), fn i -> %{day: Date.add(~D[2000-01-01], rem(i, 20_000))} end},
      {:new_type, mapping("c/{code}"), fn i -> %{code: "code-#{i}"} end},
      {:composite_encoded, mapping("orgs/{org}/people/{pid}"),
       fn i -> %{org: "eu west #{i}", pid: "w/#{i}#café"} end}
    ]
  end

  # Deterministic v4-shaped UUIDs without randomness.
  defp uuid(i) do
    h = Base.encode16(<<i::128>>, case: :lower)

    <<a::binary-size(8), b::binary-size(4), _c::binary-size(4), d::binary-size(4), e::binary-size(12)>> = h

    "#{a}-#{b}-4#{String.slice(h, 13, 3)}-#{d}-#{e}"
  end

  def workload do
    cs = cases()
    n = length(cs)

    for i <- 1..@keys do
      {label, mapping, gen} = Enum.at(cs, rem(i, n))
      {label, mapping, gen.(i)}
    end
  end

  def roundtrip(mapping, keys) do
    {:ok, iri} = AshR2RML.Subject.to_iri(mapping, keys)
    {:ok, _values} = AshR2RML.Subject.from_iri(mapping, iri)
    :ok
  end

  def time_us(mapping, keys) do
    t0 = System.monotonic_time(:nanosecond)
    :ok = roundtrip(mapping, keys)
    (System.monotonic_time(:nanosecond) - t0) / 1_000
  end

  def percentile(sorted, p) do
    idx = min(length(sorted) - 1, ceil(p * length(sorted)) - 1)
    Enum.at(sorted, max(idx, 0))
  end

  def cpk(samples) do
    n = length(samples)
    mean = Enum.sum(samples) / n
    var = Enum.reduce(samples, 0.0, fn x, acc -> acc + (x - mean) * (x - mean) end) / (n - 1)
    sigma = :math.sqrt(var)
    if sigma == 0.0, do: :infinity, else: {(@usl_us - mean) / (3 * sigma), mean, sigma}
  end

  def main do
    work = workload()

    # Warm-up: JIT-free BEAM, but primes atom/regex/type caches.
    for {_l, m, k} <- Enum.take(work, 600), do: roundtrip(m, k)

    samples = for {_l, m, k} <- work, do: time_us(m, k)
    sorted = Enum.sort(samples)
    p99 = percentile(sorted, 0.99)

    {cpk_value, mean, sigma} =
      case cpk(samples) do
        :infinity -> {1.0e9, Enum.sum(samples) / length(samples), 0.0}
        {c, mu, s} -> {c, mu, s}
      end

    per_case =
      work
      |> Enum.zip(samples)
      |> Enum.group_by(fn {{l, _, _}, _} -> l end, fn {_, t} -> t end)
      |> Map.new(fn {l, ts} -> {l, percentile(Enum.sort(ts), 0.99)} end)

    detail = %{
      keys: length(samples),
      mean_us: mean,
      sigma_us: sigma,
      p50_us: percentile(sorted, 0.50),
      p99_us: p99,
      max_us: List.last(sorted),
      cpk: cpk_value,
      p99_by_case_us: per_case
    }

    IO.inspect(detail, label: "B1 subject codec")

    breaches =
      [
        {"b1.p99_us <= #{@p99_max_us}", p99 <= @p99_max_us, detail},
        {"b1.cpk >= #{@cpk_min}", cpk_value >= @cpk_min, detail}
      ]
      |> Enum.reject(fn {_name, ok?, _detail} -> ok? end)

    AshR2RML.Bench.Stats.exit_with(breaches)
  end
end

B1.Run.main()
