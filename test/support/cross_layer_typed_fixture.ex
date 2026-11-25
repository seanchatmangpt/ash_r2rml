# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.CrossLayerEquivalenceAll.TypedFixture do
  @moduledoc false

  # `<name>.Domain` + `<name>.Person` (same shape `AshR2RML.DataLayerContract.typed_triples/3` reads)
  # with one attribute per RDF datatype family the string-flattening court cannot tell apart.
  defmacro define(name, data_layer, do: layer_dsl) do
    name = Macro.expand(name, __CALLER__)
    data_layer = Macro.expand(data_layer, __CALLER__)
    domain = Module.concat(name, Domain)
    person = Module.concat(name, Person)

    quote do
      defmodule unquote(domain) do
        use Ash.Domain, validate_config_inclusion?: false

        resources do
          resource unquote(person)
        end
      end

      defmodule unquote(person) do
        use Ash.Resource,
          domain: unquote(domain),
          data_layer: unquote(data_layer),
          extensions: [AshR2RML.Resource]

        unquote(layer_dsl)

        r2rml do
          table_name("xl_typed_people")
          class("http://schema.org/Person")
          subject(template: "urn:uuid:{pid}")
          property(:name, "http://schema.org/name")
          property(:age, "http://schema.org/age")
          property(:active, "http://schema.org/active")
          property(:price, "http://schema.org/price")
          property(:born_on, "http://schema.org/birthDate")
          property(:seen_at, "http://schema.org/dateModified")
          property(:ref, "http://schema.org/identifier")
        end

        actions do
          defaults [:read, :destroy]

          create :create do
            primary? true
            accept [:pid, :name, :age, :active, :price, :born_on, :seen_at, :ref]
          end
        end

        attributes do
          attribute :pid, :string, primary_key?: true, allow_nil?: false, public?: true
          attribute :name, :string, public?: true
          attribute :age, :integer, public?: true
          attribute :active, :boolean, public?: true
          attribute :price, :decimal, public?: true
          attribute :born_on, :date, public?: true
          attribute :seen_at, :utc_datetime_usec, public?: true
          attribute :ref, :uuid, public?: true
        end
      end
    end
  end
end
