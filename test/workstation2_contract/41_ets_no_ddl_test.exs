# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.EtsNoDdlTest do
  @moduledoc """
  An `Ash.DataLayer.Ets` resource compiles and renders to R2RML; the output is a mapping
  document and never carries SQL DDL.
  """
  use ExUnit.Case, async: true

  defmodule Gadget do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :label, :string, allow_nil?: false, public?: true
    end

    r2rml do
      table_name("ws2_gadgets")
      class("https://schema.org/Gadget")

      subject do
        template("urn:uuid:{id}")
      end

      property(:label, "http://www.w3.org/2000/01/rdf-schema#label")
    end
  end

  test "ETS resource compiles and renders without SQL DDL" do
    assert {:ok, bundle} = AshR2RML.Compiler.compile(Gadget)
    assert {:ok, ttl} = AshR2RML.R2RML.render(bundle)

    assert ttl =~ "rr:TriplesMap"
    assert ttl =~ ~s(rr:tableName "ws2_gadgets")
    refute ttl =~ ~r/CREATE\s+TABLE/i
  end
end
