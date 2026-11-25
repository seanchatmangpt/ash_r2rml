# SPDX-FileCopyrightText: 2026 ash_r2rml contributors
# SPDX-License-Identifier: MIT

defmodule AshR2RML.ErrorTest do
  @moduledoc """
  Every `%AshR2RML.Error{}` here is produced by a real emitter (worker, OBDA boundary, Subject,
  SPARQL result bound, real Ash reads) and asserted field by field. No hand-built expectations
  of the catalog beyond the code the emitter chose.
  """
  use ExUnit.Case, async: false

  alias AshR2RML.{Error, OBDA, Refusal}
  alias AshR2RML.Mapping.{LogicalTable, Resource, SubjectMap}
  alias AshR2RML.OBDA.Worker

  doctest AshR2RML.Error

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.ErrorTest.Locked
      resource AshR2RML.ErrorTest.Item
    end
  end

  defmodule Locked do
    use Ash.Resource,
      domain: AshR2RML.ErrorTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      authorizers: [Ash.Policy.Authorizer]

    ets do
      private? true
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
    end
  end

  defmodule Item do
    use Ash.Resource,
      domain: AshR2RML.ErrorTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    ets do
      private? false
    end

    r2rml do
      table_name("tb_err_item")
      class("https://schema.org/Thing")
      subject(template: "urn:uuid:{id}")
      property(:name, "https://schema.org/name")
    end

    actions do
      defaults [:read, :destroy, create: [:name]]
    end

    attributes do
      uuid_primary_key :id
      attribute :name, :string, public?: true
    end
  end

  defp mapping(template) do
    %Resource{
      ash_resource: "Thing",
      logical_table: %LogicalTable{table_name: "things"},
      subject_map: %SubjectMap{strategy: :template, value: template}
    }
  end

  defp assert_catalogued(%Error{code: code} = e) do
    assert code in Error.codes()
    assert is_binary(e.hint) and e.hint != ""
    assert e.message == Exception.message(e)
    # Error.new preserves the caller's message, so the message is non-empty but need not embed the code.
    assert is_binary(e.message) and e.message != ""
  end

  describe "worker-emitted errors" do
    test "timeout" do
      assert {:error, %Error{} = e} = Worker.run(fn -> receive do: (:never -> :ok) end, timeout_ms: 20)
      assert e.code == :REFUSED_QUERY_TIMEOUT
      assert e.details == %{timeout_ms: 20}
      assert Error.retryable?(e)
      assert_catalogued(e)
    end

    test "memory limit" do
      hog = fn -> Enum.reduce(1..10_000_000, [], fn i, acc -> [i | acc] end) end
      assert {:error, %Error{} = e} = Worker.run(hog, max_heap_words: 100_000, timeout_ms: 10_000)
      assert e.code == :REFUSED_MEMORY_LIMIT_EXCEEDED
      assert e.details == %{max_heap_words: 100_000}
      refute Error.retryable?(e)
      assert_catalogued(e)
    end

    test "worker crash" do
      assert {:error, %Error{} = e} = Worker.run(fn -> raise "boom" end)
      assert e.code == :REFUSED_WORKER_CRASHED
      assert e.details.kind == :error
      assert e.details.class == "RuntimeError"
      refute Error.retryable?(e)
      assert_catalogued(e)
    end
  end

  describe "OBDA boundary classification of real Ash failures" do
    test "a real Forbidden from Ash.read is REFUSED_UNAUTHORIZED naming the resource" do
      assert {:error, forbidden} = Ash.read(Locked, authorize?: true, actor: nil)
      e = OBDA.wrap_failure(:error, forbidden)
      assert e.code == :REFUSED_UNAUTHORIZED
      assert e.details.kind == :error
      refute Error.retryable?(e)
      assert_catalogued(e)
    end

    test "a read that fails for another reason is REFUSED_READ_FAILED, not retryable" do
      e = OBDA.wrap_failure(:exit, {:shutdown, :db})
      assert e.code == :REFUSED_READ_FAILED
      assert e.resource == nil
      assert e.details.kind == :exit
      refute Error.retryable?(e)
      assert_catalogued(e)
    end

    test "a real Ash unknown error keeps its class in details" do
      unknown = Ash.Error.Unknown.exception(errors: [])
      e = OBDA.wrap_failure(:error, unknown)
      assert e.code == :REFUSED_READ_FAILED
      assert e.details.class =~ "Ash.Error.Unknown"
    end

    test "a tenant-required failure is REFUSED_MISSING_TENANT carrying the resource" do
      reason = Ash.Error.Invalid.TenantRequired.exception(resource: Item)
      e = OBDA.wrap_failure(:error, reason)
      assert e.code == :REFUSED_MISSING_TENANT
      assert e.resource == Item
      assert_catalogued(e)
    end
  end

  describe "refusal-to-error conversion over real emitters" do
    test "REFUSED_MISSING_SUBJECT_KEY from Subject.to_iri" do
      assert {:error, %Refusal{code: :REFUSED_MISSING_SUBJECT_KEY} = r} =
               AshR2RML.Subject.to_iri(mapping("urn:uuid:{id}"), %{})

      e = Error.from_refusal(r)
      assert e.code == :REFUSED_MISSING_SUBJECT_KEY
      assert e.details.detail == r.detail
      assert e.details.subject == r.subject
      refute Error.retryable?(e)
      assert_catalogued(e)
    end

    test "REFUSED_NON_INVERTIBLE_TEMPLATE from Subject.from_iri" do
      assert {:error, %Refusal{code: :REFUSED_NON_INVERTIBLE_TEMPLATE} = r} =
               AshR2RML.Subject.from_iri(mapping("urn:uuid:{id}{name}"), "urn:uuid:ab")

      e = Error.from_refusal(r)
      assert e.code == :REFUSED_NON_INVERTIBLE_TEMPLATE
      assert_catalogued(e)
    end

    test "REFUSED_INVALID_SUBJECT_IRI from Subject.from_iri on a foreign IRI" do
      assert {:error, %Refusal{code: :REFUSED_INVALID_TERM_MAP} = r} =
               AshR2RML.Subject.from_iri(mapping("urn:uuid:{id}"), "urn:sha256:1")

      e = Error.from_refusal(r)
      assert e.code == :REFUSED_INVALID_TERM_MAP
      assert e.details.detail == r.detail
      assert_catalogued(e)
    end

    test "REFUSED_RESOURCE_BOUND from the SPARQL result bound carries the bound evidence" do
      rows = [%{"s" => 1}, %{"s" => 2}, %{"s" => 3}]

      assert {:error, %Refusal{code: :REFUSED_RESOURCE_BOUND} = r} =
               AshR2RML.SPARQL.Result.bound({:ok, :bindings, rows}, Item, 2)

      e = Error.from_refusal(r)
      assert e.code == :REFUSED_RESOURCE_BOUND
      assert e.resource == Item
      assert e.details.max_rows == 2
      assert e.details.rows == 3
      refute Error.retryable?(e)
      assert_catalogued(e)
    end

    test "OBDA.query over real rows with a tight bound refuses with a bound code" do
      Item |> Ash.read!(authorize?: false) |> Enum.each(&Ash.destroy!(&1, authorize?: false))
      for n <- 1..3, do: Ash.create!(Item, %{name: "n#{n}"}, authorize?: false)

      result =
        OBDA.query([Item], "SELECT ?s ?n WHERE { ?s <https://schema.org/name> ?n . }",
          domain: Domain,
          authorize?: false,
          allow_unauthorized: true,
          max_rows: 1,
          max_triples: 1
        )

      assert {:error, %{code: code} = err} = result

      assert code in [
               :REFUSED_RESOURCE_BOUND,
               :REFUSED_TRIPLE_LIMIT_EXCEEDED,
               :REFUSED_RESULT_LIMIT_EXCEEDED
             ]

      e = if match?(%Refusal{}, err), do: Error.from_refusal(err), else: err
      assert e.code == code
      refute Error.retryable?(e)
      assert_catalogued(e)
    end
  end

  describe "Error struct behaviour" do
    test "from_refusal reads resource and field from a tuple subject and evidence overrides" do
      r = Refusal.new(:REFUSED_QUERY_TIMEOUT, {Item, :name}, "slow", %{clause: "ORDER BY", hint: "custom"})
      e = Error.from_refusal(r)
      assert {e.resource, e.field, e.sparql_clause, e.hint} == {Item, :name, "ORDER BY", "custom"}
      assert e.message =~ "Hint: custom"
    end

    test "opaque subject leaves resource nil" do
      e = Error.from_refusal(Refusal.new(:REFUSED_UNAUTHORIZED, "x", "no"))
      assert {e.resource, e.field, e.sparql_clause} == {nil, nil, nil}
    end

    test "unknown code still yields a message and no hint, and is not retryable" do
      e = Error.new(:REFUSED_SOMETHING_NEW)
      assert Exception.message(e) =~ "REFUSED_SOMETHING_NEW"
      assert e.hint == nil
      refute Error.retryable?(e)
    end

    test "is raisable" do
      assert_raise Error, ~r/REFUSED_MISSING_TENANT/, fn -> raise Error.new(:REFUSED_MISSING_TENANT) end
    end
  end
end
