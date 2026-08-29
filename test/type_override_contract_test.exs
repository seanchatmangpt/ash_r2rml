defmodule AshR2RML.TypeOverrideContractTest do
  use ExUnit.Case, async: true

  defmodule LiteralType do
    use AshR2RML.Type,
      xsd_datatype: "http://www.w3.org/2001/XMLSchema#string"

    @impl AshR2RML.Type
    def from_rdf_lexical("known"), do: {:ok, :decoded}
    def from_rdf_lexical(value), do: {:error, {:unexpected_lexical, value}}
  end

  defmodule IriType do
    use AshR2RML.Type,
      semantic_kind: :iri,
      datatype_iri: nil

    @impl AshR2RML.Type
    def from_rdf_lexical(iri), do: {:ok, {:iri_value, iri}}
  end

  test "consumer lexical decoder overrides the generated fallback" do
    assert {:ok, :decoded} =
             AshR2RML.Type.decode(
               LiteralType,
               {:literal, "known", "http://www.w3.org/2001/XMLSchema#string"}
             )

    assert {:error, {:unexpected_lexical, "other"}} =
             AshR2RML.Type.decode(
               LiteralType,
               {:literal, "other", "http://www.w3.org/2001/XMLSchema#string"}
             )
  end

  test "IRI semantic kinds decode through the same overridable lexical contract" do
    assert {:ok, {:iri_value, "https://example.test/resource"}} =
             AshR2RML.Type.decode(IriType, {:iri, "https://example.test/resource"})
  end

  test "literal semantic kinds refuse IRI terms instead of relying on impossible branches" do
    assert {:error, :rdf_term_kind_mismatch} =
             AshR2RML.Type.decode(LiteralType, {:iri, "https://example.test/resource"})
  end
end
