# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Red2DomainVerifierCycleTest do
  # Domain declared BEFORE its member resources, members referencing the domain:
  # a compile cycle. A strict domain with an off-allowlist mapping must still be
  # refused, deterministically, never silently admitted.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  @offlist_host "example" <> ".invalid"

  defp unique, do: "C#{System.unique_integer([:positive])}"

  defp resource_source(name, domain, table, class) do
    """
    defmodule #{name} do
      @moduledoc false
      use Ash.Resource,
        domain: #{domain},
        data_layer: Ash.DataLayer.Ets,
        extensions: [AshR2RML.Resource]

      ets do
        private?(false)
      end

      attributes do
        uuid_primary_key :id
        attribute :name, :string, public?: true
      end

      r2rml do
        table_name("#{table}")
        class("#{class}")

        subject do
          template("urn:uuid:{id}")
        end

        property(:name, "http://schema.org/name")
      end
    end
    """
  end

  defp domain_source(domain, resources) do
    members = Enum.map_join(resources, "\n", &"    resource #{&1}")

    """
    defmodule #{domain} do
      @moduledoc false
      use Ash.Domain, validate_config_inclusion?: false, extensions: [AshR2RML.Domain]

      r2rml_domain do
        strict? true
      end

      resources do
    #{members}
      end
    end
    """
  end

  defp compile_cycle(domain_first?) do
    s = unique()
    domain = "AshR2RML.Red2Cycle.Dom#{s}"
    a = "AshR2RML.Red2Cycle.A#{s}"
    b = "AshR2RML.Red2Cycle.B#{s}"
    bad = "https://example.invalid/ns/Thing"

    parts = [
      resource_source(a, domain, "red2_a_#{s}", bad),
      resource_source(b, domain, "red2_b_#{s}", "http://schema.org/Person")
    ]

    dom = domain_source(domain, [a, b])
    source = Enum.join(if(domain_first?, do: [dom | parts], else: parts ++ [dom]), "\n")

    stderr =
      capture_io(:stderr, fn ->
        outcome =
          try do
            Code.compile_string(source)
            :compiled
          rescue
            e -> {:raised, Exception.message(e)}
          end

        send(self(), {:outcome, outcome})
      end)

    outcome =
      receive do
        {:outcome, o} -> o
      end

    text =
      case outcome do
        {:raised, message} -> message <> stderr
        :compiled -> stderr
      end

    {outcome, text}
  end

  test "control: resources compiled before the strict domain are refused" do
    {_outcome, text} = compile_cycle(false)
    assert text =~ "strict mode: class IRI", "no refusal: #{text}"
    assert text =~ @offlist_host
  end

  test "strict domain declared before its cyclic members is still refused" do
    {_outcome, text} = compile_cycle(true)
    assert text =~ "strict mode: class IRI", "strict check skipped in cycle: #{text}"
    assert text =~ @offlist_host
  end

  test "cyclic strict refusal is deterministic across repeated compiles" do
    verdicts =
      for _ <- 1..3 do
        {_outcome, text} = compile_cycle(true)
        text =~ "strict mode: class IRI"
      end

    assert verdicts == [true, true, true]
  end

  test "domain_errors surfaces unavailable members instead of dropping them" do
    refusal =
      AshR2RML.Refusal.new(
        :REFUSED_INVALID_OPTION,
        Missing.Red2Member,
        "Missing.Red2Member is not compiled (:unavailable)",
        %{option: :resource, reason: :compile_pending}
      )

    errors =
      AshR2RML.Domain.Verifier.domain_errors(
        [Missing.Red2Member],
        %{Missing.Red2Member => refusal},
        true,
        ["urn:uuid:"]
      )

    assert Enum.any?(errors, &(&1 =~ "Missing.Red2Member")), "dropped: #{inspect(errors)}"
  end
end
