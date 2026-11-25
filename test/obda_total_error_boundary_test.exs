# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OBDATotalErrorBoundaryTest do
  @moduledoc """
  `AshR2RML.OBDA.query/3` never raises and never leaks a raw Ash/Splode exception: every
  failure is `{:error, %AshR2RML.Error{} | %AshR2RML.Refusal{}}`.
  """
  use ExUnit.Case, async: false

  alias AshR2RML.{Error, OBDA, Refusal}

  defmodule RaisingRead do
    use Ash.Resource.ManualRead

    @impl true
    def read(_query, _data_layer_query, _opts, _context), do: raise("boom from read")
  end

  defmodule ErrorRead do
    use Ash.Resource.ManualRead

    @impl true
    def read(_query, _data_layer_query, _opts, _context),
      do: {:error, Ash.Error.Unknown.exception(errors: [Ash.Error.Unknown.UnknownError.exception(error: "db down")])}
  end

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.OBDATotalErrorBoundaryTest.Raising
      resource AshR2RML.OBDATotalErrorBoundaryTest.Failing
      resource AshR2RML.OBDATotalErrorBoundaryTest.Locked
    end
  end

  defmodule Raising do
    use Ash.Resource,
      domain: AshR2RML.OBDATotalErrorBoundaryTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML]

    ets do
      private? true
    end

    r2rml do
      class_iri("https://example.org/Raising")
      subject_template("https://example.org/Raising/{id}")
      table_name("tb_raising")
      attribute_mappings([{:name, "https://example.org/name"}])
    end

    actions do
      read :read do
        primary? true
        manual AshR2RML.OBDATotalErrorBoundaryTest.RaisingRead
      end
    end

    attributes do
      uuid_primary_key :id
      attribute :name, :string, public?: true
    end
  end

  defmodule Failing do
    use Ash.Resource,
      domain: AshR2RML.OBDATotalErrorBoundaryTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML]

    ets do
      private? true
    end

    r2rml do
      class_iri("https://example.org/Failing")
      subject_template("https://example.org/Failing/{id}")
      table_name("tb_failing")
      attribute_mappings([{:name, "https://example.org/name"}])
    end

    actions do
      read :read do
        primary? true
        manual AshR2RML.OBDATotalErrorBoundaryTest.ErrorRead
      end
    end

    attributes do
      uuid_primary_key :id
      attribute :name, :string, public?: true
    end
  end

  defmodule Locked do
    use Ash.Resource,
      domain: AshR2RML.OBDATotalErrorBoundaryTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      authorizers: [Ash.Policy.Authorizer],
      extensions: [AshR2RML]

    ets do
      private? true
    end

    r2rml do
      class_iri("https://example.org/Locked")
      subject_template("https://example.org/Locked/{id}")
      table_name("tb_locked")
      attribute_mappings([{:name, "https://example.org/name"}])
    end

    policies do
      policy always() do
        forbid_if always()
      end
    end

    actions do
      defaults [:read]
    end

    attributes do
      uuid_primary_key :id
      attribute :name, :string, public?: true
    end
  end

  @sparql "SELECT ?s ?name WHERE { ?s <https://example.org/name> ?name . }"

  defp typed?({:error, %Error{code: code}}), do: is_atom(code)
  defp typed?({:error, %Refusal{code: code}}), do: is_atom(code)
  defp typed?(_), do: false

  test "a read that raises becomes a typed error, never an exception" do
    result =
      OBDA.query([Raising], @sparql,
        domain: Domain,
        authorize?: false,
        allow_unauthorized: true
      )

    assert typed?(result)
    assert {:error, %Error{details: details}} = result
    assert is_map(details)
  end

  test "a read returning {:error, %Ash.Error.Unknown{}} is wrapped" do
    result =
      OBDA.query([Failing], @sparql,
        domain: Domain,
        authorize?: false,
        allow_unauthorized: true
      )

    assert typed?(result)
    # InMemory fails closed first with a typed Refusal naming the original error class; OBDA never
    # lets the raw Ash.Error.Unknown struct escape.
    assert {:error, %Refusal{code: code, evidence: evidence}} = result
    assert is_atom(code)
    assert evidence.error_class =~ "Ash.Error.Unknown"
    refute match?({:error, %{__struct__: Ash.Error.Unknown}}, result)
  end

  test "an unauthorized read is a typed refusal or a pruned-by-policy result" do
    result = OBDA.query([Locked], @sparql, domain: Domain, actor: nil)

    case result do
      {:ok, res} -> assert res.stats.resources_pruned_by_policy == 1
      other -> assert typed?(other)
    end
  end

  test "normalize_result classifies raw Ash/Splode errors and bare terms" do
    forbidden = Ash.Error.Forbidden.exception(errors: [])

    assert {:error, %Error{code: :REFUSED_UNAUTHORIZED}} =
             OBDA.normalize_result({:error, forbidden})

    unknown = Ash.Error.Unknown.exception(errors: [])
    assert {:error, %Error{code: :REFUSED_READ_FAILED}} = OBDA.normalize_result({:error, unknown})
    assert {:error, %Error{code: :REFUSED_READ_FAILED}} = OBDA.normalize_result({:error, :nope})
    assert {:error, %Error{}} = OBDA.normalize_result(:weird)

    refusal = Refusal.new(:REFUSED_UNSUPPORTED_SPARQL_FEATURE, nil, "x", %{})
    assert {:error, ^refusal} = OBDA.normalize_result({:error, refusal})
  end

  test "exit and throw inside the pipeline map to typed errors" do
    assert %Error{code: :REFUSED_READ_FAILED, details: %{kind: :exit}} =
             OBDA.wrap_failure(:exit, {:shutdown, :db})

    assert %Error{details: %{kind: :throw}} = OBDA.wrap_failure(:throw, :ball)
  end
end
