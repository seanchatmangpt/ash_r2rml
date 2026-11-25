# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW16ContractTypes.Fixture do
  @moduledoc false

  # `<name>.Domain` + `<name>.Row`: one attribute per scalar family the shapes resource lacks.
  defmacro define(name, data_layer, do: layer_dsl) do
    name = Macro.expand(name, __CALLER__)
    data_layer = Macro.expand(data_layer, __CALLER__)
    domain = Module.concat(name, Domain)
    row = Module.concat(name, Row)

    quote do
      defmodule unquote(domain) do
        use Ash.Domain, validate_config_inclusion?: false

        resources do
          resource unquote(row)
        end
      end

      defmodule unquote(row) do
        use Ash.Resource,
          domain: unquote(domain),
          data_layer: unquote(data_layer),
          extensions: [AshR2RML.Resource]

        unquote(layer_dsl)

        r2rml do
          table_name("w16_typed_rows")
          class("http://schema.org/Thing")
          subject(template: "urn:uuid:{pid}")
          property(:flag, "http://schema.org/active")
          property(:born_on, "http://schema.org/birthDate")
          property(:amount, "http://schema.org/price")
          property(:ref, "http://schema.org/identifier")
          property(:seen_at, "http://schema.org/dateModified")
        end

        actions do
          defaults [:read, :destroy]

          create :create do
            primary? true
            accept [:pid, :flag, :born_on, :amount, :ref, :seen_at]
          end
        end

        attributes do
          attribute :pid, :string, primary_key?: true, allow_nil?: false, public?: true
          attribute :flag, :boolean, public?: true
          attribute :born_on, :date, public?: true
          attribute :amount, :decimal, public?: true
          attribute :ref, :uuid, public?: true
          attribute :seen_at, :utc_datetime, public?: true
        end
      end
    end
  end
end
