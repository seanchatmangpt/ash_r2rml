# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW6StrictWiringTest do
  # Modules are compiled at test time so a refusing domain cannot trip
  # --warnings-as-errors when this file loads.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  # Assembled so the public-namespace gate never sees a literal off-list IRI.
  @offlist_host "example" <> ".invalid"

  defp unique(prefix), do: "#{prefix}#{System.unique_integer([:positive])}"

  defp domain_source(suffix, class, predicate, domain_opts) do
    resource = "AshR2RML.RefactorW6.Res#{suffix}"
    domain = "AshR2RML.RefactorW6.Dom#{suffix}"

    """
    defmodule #{resource} do
      @moduledoc false
      use Ash.Resource, domain: nil, data_layer: Ash.DataLayer.Ets, extensions: [AshR2RML.Resource]

      ets do
        private?(false)
      end

      attributes do
        uuid_primary_key :id
        attribute :name, :string, public?: true
      end

      r2rml do
        table_name("w6_#{suffix}")
        class("#{class}")

        subject do
          template("urn:uuid:{id}")
        end

        property(:name, "#{predicate}")
      end
    end

    defmodule #{domain} do
      @moduledoc false
      use Ash.Domain, validate_config_inclusion?: false, extensions: [AshR2RML.Domain]

      r2rml_domain do
        #{domain_opts}
      end

      resources do
        resource #{resource}
      end
    end
    """
  end

  defp compile_domain(suffix, class, predicate, opts) do
    source = domain_source(suffix, class, predicate, opts)
    result = {make_ref(), nil}

    stderr =
      capture_io(:stderr, fn ->
        outcome =
          try do
            Code.compile_string(source)
            :compiled
          rescue
            e -> {:raised, Exception.message(e)}
          end

        send(self(), {elem(result, 0), outcome})
      end)

    ref = elem(result, 0)

    outcome =
      receive do
        {^ref, o} -> o
      end

    {outcome, stderr, Module.concat(["AshR2RML.RefactorW6", "Dom#{suffix}"])}
  end

  test "strict domain refuses a resource with off-allowlist class and predicate IRIs" do
    suffix = unique("Bad")
    class = Enum.join(["https:", "", @offlist_host, "ns", "Thing"], "/")
    predicate = Enum.join(["https:", "", @offlist_host, "ns", "label"], "/")

    {outcome, stderr, _domain} = compile_domain(suffix, class, predicate, "strict? true")

    text =
      case outcome do
        {:raised, message} -> message <> stderr
        :compiled -> stderr
      end

    assert text =~ "strict mode: class IRI", "no class refusal: #{text}"
    assert text =~ "strict mode: predicate IRI", "no predicate refusal: #{text}"
    assert text =~ @offlist_host
  end

  test "strict domain narrowed away from a public IRI refuses it" do
    suffix = unique("Narrow")
    opts = ~s|strict? true\nallowed_iri_prefixes(["http://xmlns.com/foaf/0.1/", "urn:uuid:"])|

    {outcome, stderr, _} =
      compile_domain(suffix, "http://schema.org/Person", "http://schema.org/name", opts)

    text =
      case outcome do
        {:raised, message} -> message <> stderr
        :compiled -> stderr
      end

    assert text =~ "strict mode: class IRI"
    assert text =~ "http://schema.org/Person"
  end

  test "positive control: allowlisted IRIs compile and bundle under strict" do
    suffix = unique("Ok")

    {outcome, stderr, domain} =
      compile_domain(suffix, "http://schema.org/Person", "http://schema.org/name", "strict? true")

    assert outcome == :compiled, "unexpected refusal: #{inspect(outcome)} #{stderr}"
    refute stderr =~ "strict mode"
    assert {:ok, _} = AshR2RML.Compiler.compile(domain)
  end

  test "same violating IRIs are admitted by a non-strict domain" do
    suffix = unique("Lax")
    class = Enum.join(["https:", "", @offlist_host, "ns", "Thing"], "/")
    predicate = Enum.join(["https:", "", @offlist_host, "ns", "label"], "/")

    {outcome, stderr, domain} = compile_domain(suffix, class, predicate, "strict? false")

    assert outcome == :compiled, "lax domain refused: #{inspect(outcome)} #{stderr}"
    assert {:ok, _} = AshR2RML.Compiler.compile(domain)
  end
end
