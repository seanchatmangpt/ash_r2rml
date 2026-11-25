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
      resource AshR2RML.OBDATotalErrorBoundaryTest.PrivateTable
    end
  end

  # Private ETS tables are refused before any read (the worker process cannot see them), so the
  # resources that must reach the read path use a shared (non-private) table.
  defmodule PrivateTable do
    use Ash.Resource,
      domain: AshR2RML.OBDATotalErrorBoundaryTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    ets do
      private? true
    end

    r2rml do
      table_name("tb_private")
      class("https://schema.org/Thing")
      subject(template: "urn:uuid:{id}")
      property(:name, "https://schema.org/name")
    end

    actions do
      defaults [:read]
    end

    attributes do
      uuid_primary_key :id
      attribute :name, :string, public?: true
    end
  end

  defmodule Raising do
    use Ash.Resource,
      domain: AshR2RML.OBDATotalErrorBoundaryTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    r2rml do
      table_name("tb_raising")
      class("https://schema.org/Thing")
      subject(template: "urn:uuid:{id}")
      property(:name, "https://schema.org/name")
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
      extensions: [AshR2RML.Resource]

    r2rml do
      table_name("tb_failing")
      class("https://schema.org/Thing")
      subject(template: "urn:uuid:{id}")
      property(:name, "https://schema.org/name")
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
      extensions: [AshR2RML.Resource]

    r2rml do
      table_name("tb_locked")
      class("https://schema.org/Thing")
      subject(template: "urn:uuid:{id}")
      property(:name, "https://schema.org/name")
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

  @sparql "SELECT ?s ?name WHERE { ?s <https://schema.org/name> ?name . }"

  test "a read that raises becomes a typed refusal naming the raised class, never an exception" do
    # The raise escapes InMemory's rescue as an Ash.Error.Unknown and is classified by the
    # OBDA boundary as a typed REFUSED_READ_FAILED carrying only the exception class.
    assert {:error, %Error{code: :REFUSED_READ_FAILED, details: details}} =
             OBDA.query([Raising], @sparql,
               domain: Domain,
               authorize?: false,
               allow_unauthorized: true
             )

    assert %{kind: :error, class: "Ash.Error.Unknown", reason: reason} = details
    assert reason =~ "boom from read"
  end

  test "a read returning {:error, %Ash.Error.Unknown{}} is wrapped" do
    # InMemory fails closed first with a typed Refusal naming the original error class; OBDA never
    # lets the raw Ash.Error.Unknown struct escape.
    assert {:error, %Error{code: :REFUSED_UNSUPPORTED_SPARQL_FEATURE, resource: Failing, details: evidence}} =
             OBDA.query([Failing], @sparql,
               domain: Domain,
               authorize?: false,
               allow_unauthorized: true
             )

    assert evidence.resource == Failing
    assert evidence.error_class == "Ash.Error.Unknown"
  end

  test "a private ETS table is refused before any read, as a typed Error" do
    assert {:error, %Error{code: :REFUSED_PRIVATE_DATA_LAYER, resource: PrivateTable, details: details}} =
             OBDA.query([PrivateTable], @sparql, domain: Domain, authorize?: false, allow_unauthorized: true)

    assert details.detail =~ "private ETS table"
  end

  test "an actor denied by policy gets an ok result with the resource pruned and no bindings" do
    assert {:ok, res} = OBDA.query([Locked], @sparql, domain: Domain, actor: nil)

    assert res.stats.resources_pruned_by_policy == 1
    assert res.bindings == []
    assert res.stats.rows_read == 0
  end

  test "normalize_result classifies raw Ash/Splode errors and bare terms" do
    forbidden = Ash.Error.Forbidden.exception(errors: [])

    assert {:error, %Error{code: :REFUSED_UNAUTHORIZED}} =
             OBDA.normalize_result({:error, forbidden})

    unknown = Ash.Error.Unknown.exception(errors: [])

    assert {:error, %Error{code: :REFUSED_READ_FAILED, details: %{kind: :error, class: "Ash.Error.Unknown"}}} =
             OBDA.normalize_result({:error, unknown})

    assert {:error, %Error{code: :REFUSED_READ_FAILED, details: %{kind: :error, class: nil}}} =
             OBDA.normalize_result({:error, :nope})

    assert {:error, %Error{code: :REFUSED_READ_FAILED, details: %{kind: :error, class: nil}}} =
             OBDA.normalize_result(:weird)

    refusal = Refusal.new(:REFUSED_UNSUPPORTED_SPARQL_FEATURE, nil, "x", %{})

    assert {:error, %Error{code: :REFUSED_UNSUPPORTED_SPARQL_FEATURE}} =
             OBDA.normalize_result({:error, refusal})
  end

  test "exit and throw inside the pipeline map to typed errors" do
    assert %Error{code: :REFUSED_READ_FAILED, details: %{kind: :exit}} =
             OBDA.wrap_failure(:exit, {:shutdown, :db})

    assert %Error{code: :REFUSED_READ_FAILED, details: %{kind: :throw, class: nil}} =
             OBDA.wrap_failure(:throw, :ball)
  end
end
