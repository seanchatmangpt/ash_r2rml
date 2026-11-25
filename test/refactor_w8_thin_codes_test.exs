# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW8ThinCodesTest do
  @moduledoc """
  Real-trigger coverage for four thinly tested refusal codes, each with a positive control.
  """
  use ExUnit.Case, async: true

  alias AshR2RML.Datatype.Registry
  alias AshR2RML.Error
  alias AshR2RML.Introspection.Manifest
  alias AshR2RML.OBDA.Preflight
  alias AshR2RML.OBDA.Worker
  alias AshR2RML.Refusal

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      allow_unregistered?(true)
    end
  end

  defmodule Tenanted do
    use Ash.Resource, domain: AshR2RML.RefactorW8ThinCodesTest.Domain, data_layer: Ash.DataLayer.Ets

    ets do
      private?(false)
    end

    multitenancy do
      strategy(:attribute)
      attribute(:org_id)
    end

    actions do
      defaults([:read])
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:org_id, :string, public?: true)
    end
  end

  defmodule IriOnlyType do
    use Ash.Type
    use AshR2RML.Type, semantic_kind: :iri

    @impl Ash.Type
    def storage_type(_), do: :string

    @impl Ash.Type
    def cast_input(value, _), do: {:ok, value}

    @impl Ash.Type
    def cast_stored(value, _), do: {:ok, value}

    @impl Ash.Type
    def dump_to_native(value, _), do: {:ok, value}
  end

  describe "REFUSED_MANIFEST_GENERATION" do
    test "missing :otp_app is refused with the typed code" do
      assert {:error, %Refusal{code: :REFUSED_MANIFEST_GENERATION}} = Manifest.generate([])
      assert {:error, %Refusal{code: :REFUSED_MANIFEST_GENERATION}} = Manifest.resource_lookup(action_entrypoints: [])
    end

    test "positive control: explicit action entrypoints generate a manifest" do
      assert {:ok, _manifest} = Manifest.generate(otp_app: :ash_r2rml, action_entrypoints: [{Tenanted, :read}])
    end
  end

  describe "REFUSED_MISSING_TENANT" do
    test "attribute-multitenant resource without a tenant is refused" do
      assert {:error, %Refusal{code: :REFUSED_MISSING_TENANT, subject: Tenanted}} =
               Preflight.check(Tenanted, domain: Domain)
    end

    test "positive control: the same resource with a tenant passes preflight" do
      assert :ok = Preflight.check(Tenanted, domain: Domain, tenant: "org-1")
    end
  end

  describe "REFUSED_INVALID_OPTION" do
    test "non-positive timeout and heap options are refused naming the option" do
      assert {:error, %Error{code: :REFUSED_INVALID_OPTION, details: %{option: :timeout_ms}}} =
               Worker.run(fn -> :ok end, timeout_ms: 0)

      assert {:error, %Error{code: :REFUSED_INVALID_OPTION, details: %{option: :max_heap_words}}} =
               Worker.run(fn -> :ok end, max_heap_words: -5)
    end

    test "positive control: valid options run the function" do
      assert {:ok, 2} = Worker.run(fn -> 1 + 1 end, timeout_ms: 1000, max_heap_words: 1_000_000)
    end
  end

  describe "REFUSED_NON_LITERAL_DATATYPE" do
    test "a non-literal semantic Ash type is refused by the registry" do
      assert {:error, %Refusal{code: :REFUSED_NON_LITERAL_DATATYPE, subject: IriOnlyType}} =
               Registry.resolve(IriOnlyType)
    end

    test "positive control: a literal-capable type resolves" do
      assert {:ok, %{rdf_datatype: "http://www.w3.org/2001/XMLSchema#date"}} = Registry.resolve(:date)
    end
  end
end
