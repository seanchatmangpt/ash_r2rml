# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OBDAContractFixesTest do
  @moduledoc """
  Public `AshR2RML.OBDA.query/3` contract: `allow_sensitive` alias, `:action` forwarding,
  `:stop` telemetry refusal code, bound validation, private-ETS refusal and `retryable?/1`.
  Real ETS-backed Ash resources and real `:telemetry` handlers; no doubles.
  """

  use ExUnit.Case, async: false

  alias AshR2RML.Error
  alias AshR2RML.Mapping.{Datatype, LogicalTable, ObjectMap, PredicateObjectMap, Resource, SubjectMap}
  alias AshR2RML.OBDA
  alias AshR2RML.Error

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.OBDAContractFixesTest.Doc
      resource AshR2RML.OBDAContractFixesTest.Hidden
    end
  end

  defmodule Doc do
    use Ash.Resource, domain: AshR2RML.OBDAContractFixesTest.Domain, data_layer: Ash.DataLayer.Ets

    ets do
      private?(false)
    end

    actions do
      defaults([:read, :destroy, create: [:title, :token]])

      read :visible do
        filter(expr(title != "hidden"))
      end
    end

    identities do
      identity(:by_title, [:title], pre_check_with: AshR2RML.OBDAContractFixesTest.Domain)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:title, :string, allow_nil?: false, public?: true)
      attribute(:token, :string, public?: true, sensitive?: true)
    end
  end

  defmodule Hidden do
    use Ash.Resource, domain: AshR2RML.OBDAContractFixesTest.Domain, data_layer: Ash.DataLayer.Ets

    ets do
      private?(true)
    end

    actions do
      defaults([:read, :destroy, create: [:title]])
    end

    identities do
      identity(:by_title, [:title], pre_check_with: AshR2RML.OBDAContractFixesTest.Domain)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:title, :string, allow_nil?: false, public?: true)
    end
  end

  @title_pred "https://schema.org/name"
  @token_pred "https://schema.org/identifier"
  @string "http://www.w3.org/2001/XMLSchema#string"

  defp pom(attribute, predicate) do
    %PredicateObjectMap{
      attribute: attribute,
      predicate_iri: predicate,
      object_map: %ObjectMap{
        strategy: :column,
        value: Atom.to_string(attribute),
        datatype: %Datatype{ash_type: Ash.Type.String, rdf_datatype: @string}
      }
    }
  end

  defp specs(resource, template, attrs) do
    mapping = %Resource{
      ash_resource: resource,
      logical_table: %LogicalTable{table_name: Atom.to_string(resource)},
      subject_map: %SubjectMap{strategy: :template, value: template, term_type: :iri},
      class_iris: ["https://schema.org/Thing"],
      predicate_object_maps: for({attr, pred} <- attrs, do: pom(attr, pred)),
      identities: [[:title]],
      metadata: %{source: :obda_contract_fixes_test}
    }

    [{resource, mapping}]
  end

  defp doc_specs, do: specs(Doc, "urn:uuid:{title}", title: @title_pred, token: @token_pred)
  defp title_specs, do: specs(Doc, "urn:uuid:{title}", title: @title_pred)
  defp select(pred), do: "SELECT ?s ?o WHERE { ?s <#{pred}> ?o }"
  defp objects(%OBDA.Result{bindings: rows}), do: rows |> Enum.map(&to_string(&1["o"])) |> Enum.sort()

  def handle_event(_event, _measures, meta, test_pid), do: send(test_pid, {:stop_meta, meta})

  setup do
    Doc
    |> Ash.read!(authorize?: false, domain: Domain)
    |> Enum.each(&Ash.destroy!(&1, authorize?: false, domain: Domain))

    for {title, token} <- [{"shown", "tok-1"}, {"hidden", "tok-2"}] do
      Doc
      |> Ash.Changeset.for_create(:create, %{title: title, token: token}, domain: Domain)
      |> Ash.create!(authorize?: false, domain: Domain)
    end

    :ok
  end

  describe "allow_sensitive alias" do
    test "allow_sensitive: true behaves like allow_sensitive?: true" do
      assert {:ok, result} = OBDA.query(doc_specs(), select(@token_pred), domain: Domain, allow_sensitive: true)
      assert objects(result) == ["tok-1", "tok-2"]
    end

    test "allow_sensitive?: true still works and the default still refuses" do
      assert {:ok, result} = OBDA.query(doc_specs(), select(@token_pred), domain: Domain, allow_sensitive?: true)
      assert objects(result) == ["tok-1", "tok-2"]

      assert {:error, error} = OBDA.query(doc_specs(), select(@token_pred), domain: Domain)
      assert error.code == :REFUSED_SENSITIVE_ATTRIBUTE_MATERIALIZATION
    end
  end

  describe ":action forwarding" do
    test "a named read action narrows the read" do
      assert {:ok, all} = OBDA.query(title_specs(), select(@title_pred), domain: Domain, pushdown: false)
      assert objects(all) == ["hidden", "shown"]

      assert {:ok, visible} =
               OBDA.query(title_specs(), select(@title_pred), domain: Domain, pushdown: false, action: :visible)

      assert objects(visible) == ["shown"]
    end
  end

  describe "bounds" do
    for key <- [:max_rows, :max_triples, :timeout_ms, :max_heap_words], bad <- [0, -1, "5", 1.5] do
      test "#{key}: #{inspect(bad)} is refused with a typed refusal" do
        opts = [{:domain, Domain}, {unquote(key), unquote(bad)}]

        assert {:error, %Error{code: :REFUSED_INVALID_OPTION}} =
                 OBDA.query(title_specs(), select(@title_pred), opts)
      end
    end

    test "positive integer bounds are accepted" do
      assert {:ok, result} =
               OBDA.query(title_specs(), select(@title_pred),
                 domain: Domain,
                 max_rows: 10,
                 max_triples: 100,
                 timeout_ms: 5_000,
                 max_heap_words: 50_000_000
               )

      assert objects(result) == ["hidden", "shown"]
    end
  end

  describe "private ETS" do
    test "is refused with REFUSED_PRIVATE_DATA_LAYER instead of an empty result" do
      hidden = specs(Hidden, "urn:uuid:{title}", title: @title_pred)

      assert {:error, %Error{code: :REFUSED_PRIVATE_DATA_LAYER, resource: Hidden} = error} =
               OBDA.query(hidden, select(@title_pred), domain: Domain)

      assert error.code in Error.codes()
      assert is_binary(error.hint)
    end

    test "the :stop telemetry event carries the Error code" do
      id = {__MODULE__, make_ref()}
      :ok = :telemetry.attach(id, [:ash_r2rml, :obda, :query, :stop], &__MODULE__.handle_event/4, self())
      on_exit(fn -> :telemetry.detach(id) end)

      hidden = specs(Hidden, "urn:uuid:{title}", title: @title_pred)
      assert {:error, %Error{}} = OBDA.query(hidden, select(@title_pred), domain: Domain)

      assert_receive {:stop_meta, %{result: :error, code: :REFUSED_PRIVATE_DATA_LAYER}}, 1_000
    end
  end

  describe "Error.retryable?/1" do
    test "only the timeout is retryable" do
      assert Error.retryable?(:REFUSED_QUERY_TIMEOUT)
      refute Error.retryable?(:REFUSED_READ_FAILED)
      refute Error.retryable?(:REFUSED_WORKER_CRASHED)
      refute Error.retryable?(:REFUSED_PRIVATE_DATA_LAYER)
    end
  end
end
