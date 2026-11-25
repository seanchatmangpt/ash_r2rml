# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW9VerifierCascadeTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Domain.Verifier

  defmodule Thing do
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
      table_name("w9_cascade_thing")
      class("http://schema.org/Person")

      subject do
        template("urn:uuid:{id}")
      end

      property(:name, "http://schema.org/name")
      graph("urn:uuid:00000000-0000-0000-0000-0000000000a1")
    end
  end

  defp mappings do
    {:ok, m} = AshR2RML.Resource.Info.mapping_result(Thing)
    %{Thing => m}
  end

  test "invalid allowlist reports only the prefix error, no IRI cascade" do
    errors = Verifier.domain_errors([Thing], mappings(), true, ["http://schema.org"])

    assert [msg] = errors
    assert msg =~ "must end in"
    refute Enum.any?(errors, &(&1 =~ "outside the allowed ontology prefixes"))
  end

  test "valid allowlist still reports IRIs outside it" do
    errors = Verifier.domain_errors([Thing], mappings(), true, ["http://xmlns.com/foaf/0.1/", "urn:uuid:"])

    assert Enum.any?(errors, &(&1 =~ "outside the allowed ontology prefixes"))
    refute Enum.any?(errors, &(&1 =~ "must end in"))
  end

  test "non-strict domain reports nothing for the same mapping" do
    assert [] == Verifier.domain_errors([Thing], mappings(), false, ["http://schema.org"])
  end
end
