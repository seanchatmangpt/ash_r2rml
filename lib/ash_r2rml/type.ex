# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Type do
  @moduledoc """
  Behaviour and macro extension for custom Ash scalar types to declare RDF datatypes.

  Allows custom `Ash.Type` implementations to specify an XSD datatype IRI and lexical serialization.

  ## Example

      defmodule MyApp.Types.GeoPoint do
        use Ash.Type
        use AshR2RML.Type,
          xsd_datatype: "http://www.opengis.net/ont/geosparql#wktLiteral"

        @impl AshR2RML.Type
        def to_rdf_lexical(%{lat: lat, lng: lng}) do
          "POINT(\#{lng} \#{lat})"
        end
      end
  """

  @callback xsd_datatype() :: String.t()
  @callback to_rdf_lexical(term()) :: String.t()
  @callback from_rdf_lexical(String.t()) :: {:ok, term()} | {:error, term()}

  @optional_callbacks from_rdf_lexical: 1

  defmacro __using__(opts) do
    quote do
      @behaviour AshR2RML.Type

      @impl AshR2RML.Type
      def xsd_datatype do
        unquote(Keyword.get(opts, :xsd_datatype, "http://www.w3.org/2001/XMLSchema#string"))
      end

      @impl AshR2RML.Type
      def to_rdf_lexical(value) do
        to_string(value)
      end

      defoverridable xsd_datatype: 0, to_rdf_lexical: 1
    end
  end
end
