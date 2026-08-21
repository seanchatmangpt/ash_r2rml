# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.PureDslSparqlTest do
  use ExUnit.Case, async: true

  defmodule Person do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :name, :string, allow_nil?: false, public?: true
    end

    r2rml do
      table_name("people")
      class("https://schema.org/Person")

      subject do
        template("https://example.org/people/{id}")
      end

      property(:name, "https://schema.org/name")
    end

    sparql do
      query :find_all_people do
        form(:select)
        select [:name]

        where [
          {:person, "http://www.w3.org/1999/02/22-rdf-syntax-ns#type", "https://schema.org/Person"},
          {:person, "https://schema.org/name", :name}
        ]
      end

      query :count_people do
        form(:ask)

        where [
          {:person, "http://www.w3.org/1999/02/22-rdf-syntax-ns#type", "https://schema.org/Person"}
        ]
      end
    end
  end

  test "compiles pure sparql DSL queries into resource metadata" do
    queries = AshR2RML.Resource.Info.sparql_queries(Person)
    assert length(queries) == 2

    [q1, q2] = queries
    assert q1.name == :find_all_people
    assert q1.form == :select
    assert q1.select == [:name]
    assert length(q1.where) == 2

    assert q2.name == :count_people
    assert q2.form == :ask
  end
end
