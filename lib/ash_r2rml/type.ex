# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Type do
  @moduledoc """
  Semantic contract layered on top of `Ash.Type`.

  `AshR2RML.Type` preserves the original datatype/lexical callbacks while
  generalizing the contract to RDF terms whose semantics are not XSD literals.

  The public ontology remains authoritative. Implementing this behaviour only
  describes one executable Ash projection; it does not prove equivalence or
  grant persistence/actuation authority.
  """

  @type semantic_kind :: :literal | :iri | :concept | :value_object | :resource

  @type rdf_term ::
          {:literal, String.t(), String.t()}
          | {:lang_literal, String.t(), String.t()}
          | {:iri, String.t()}
          | {:node, map()}

  @callback semantic_kind() :: semantic_kind()
  @callback datatype_iri() :: String.t() | nil
  @callback class_iri() :: String.t() | nil
  @callback concept_scheme_iri() :: String.t() | nil
  @callback shacl_constraints() :: keyword() | map()
  @callback to_rdf(term()) :: rdf_term() | {:error, term()}
  @callback from_rdf(rdf_term()) :: {:ok, term()} | {:error, term()}

  # Backwards-compatible scalar datatype surface.
  @callback xsd_datatype() :: String.t() | nil
  @callback to_rdf_lexical(term()) :: String.t()
  @callback from_rdf_lexical(String.t()) :: {:ok, term()} | {:error, term()}

  @optional_callbacks from_rdf: 1, to_rdf_lexical: 1, from_rdf_lexical: 1

  @spec semantic_type?(term()) :: boolean()
  def semantic_type?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and
      function_exported?(module, :semantic_kind, 0) and
      function_exported?(module, :to_rdf, 1)
  end

  def semantic_type?(_), do: false

  @spec contract(module()) :: {:ok, map()} | :error
  def contract(module) when is_atom(module) do
    if semantic_type?(module) do
      {:ok,
       %{
         semantic_kind: module.semantic_kind(),
         datatype_iri: exported(module, :datatype_iri),
         class_iri: exported(module, :class_iri),
         concept_scheme_iri: exported(module, :concept_scheme_iri),
         shacl_constraints: exported(module, :shacl_constraints) || []
       }}
    else
      :error
    end
  end

  @spec encode(module(), term()) :: rdf_term() | {:error, term()}
  def encode(module, value) when is_atom(module) do
    if semantic_type?(module), do: module.to_rdf(value), else: {:error, :not_semantic_type}
  end

  @spec decode(module(), rdf_term()) :: {:ok, term()} | {:error, term()}
  def decode(module, term) when is_atom(module) do
    cond do
      not semantic_type?(module) ->
        {:error, :not_semantic_type}

      function_exported?(module, :from_rdf, 1) ->
        module.from_rdf(term)

      true ->
        {:error, :rdf_decoder_not_implemented}
    end
  end

  defp exported(module, callback) do
    if function_exported?(module, callback, 0), do: apply(module, callback, []), else: nil
  end

  defmacro __using__(opts) do
    semantic_kind = Keyword.get(opts, :semantic_kind, :literal)

    default_datatype = if semantic_kind == :literal, do: "http://www.w3.org/2001/XMLSchema#string"

    datatype_iri =
      Keyword.get(
        opts,
        :datatype_iri,
        Keyword.get(opts, :xsd_datatype, default_datatype)
      )

    class_iri = Keyword.get(opts, :class_iri)
    concept_scheme_iri = Keyword.get(opts, :concept_scheme_iri)
    shacl_constraints = Keyword.get(opts, :shacl_constraints, [])

    quote do
      @behaviour AshR2RML.Type

      def semantic_kind, do: unquote(semantic_kind)

      def datatype_iri, do: unquote(datatype_iri)

      def class_iri, do: unquote(class_iri)

      def concept_scheme_iri, do: unquote(concept_scheme_iri)

      def shacl_constraints, do: unquote(Macro.escape(shacl_constraints))

      def xsd_datatype, do: datatype_iri()

      # `to_rdf_lexical/1` and `from_rdf_lexical/1` are NOT injected: an
      # implementer that does not define them fails closed with a typed error.
      def to_rdf(value) do
        kind = apply(__MODULE__, :semantic_kind, [])

        cond do
          kind not in [:literal, :iri, :concept] ->
            {:error, {:semantic_encoder_not_implemented, kind}}

          not function_exported?(__MODULE__, :to_rdf_lexical, 1) ->
            {:error, :lexical_encoder_not_implemented}

          kind == :literal ->
            case datatype_iri() do
              datatype when is_binary(datatype) ->
                {:literal, apply(__MODULE__, :to_rdf_lexical, [value]), datatype}

              _ ->
                {:error, :literal_without_datatype}
            end

          true ->
            {:iri, apply(__MODULE__, :to_rdf_lexical, [value])}
        end
      end

      def from_rdf({:literal, lexical, datatype}) do
        if datatype == datatype_iri() and function_exported?(__MODULE__, :from_rdf_lexical, 1) do
          apply(__MODULE__, :from_rdf_lexical, [lexical])
        else
          {:error, :rdf_literal_not_decodable}
        end
      end

      def from_rdf({:iri, iri}) do
        kind = apply(__MODULE__, :semantic_kind, [])

        cond do
          kind not in [:iri, :concept] -> {:error, :rdf_term_kind_mismatch}
          function_exported?(__MODULE__, :from_rdf_lexical, 1) -> apply(__MODULE__, :from_rdf_lexical, [iri])
          true -> {:error, :rdf_decoder_not_implemented}
        end
      end

      def from_rdf(_), do: {:error, :rdf_term_kind_mismatch}

      defoverridable semantic_kind: 0,
                     datatype_iri: 0,
                     class_iri: 0,
                     concept_scheme_iri: 0,
                     shacl_constraints: 0,
                     xsd_datatype: 0,
                     to_rdf: 1,
                     from_rdf: 1
    end
  end
end
