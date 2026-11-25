# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.CrossLayerEquivalenceAll.Fixture do
  @moduledoc false

  @doc """
  Defines `<name>.Domain` and `<name>.Person` on `data_layer`. `layer_dsl` is spliced into the
  resource body (data-layer section). `opts[:manual]` swaps the default read/create actions for
  a manual read action.
  """
  defmacro define(name, data_layer, opts, do: layer_dsl) do
    name = Macro.expand(name, __CALLER__)
    data_layer = Macro.expand(data_layer, __CALLER__)
    domain = Module.concat(name, Domain)
    person = Module.concat(name, Person)
    manual = opts |> Keyword.get(:manual) |> then(&if(&1, do: Macro.expand(&1, __CALLER__)))

    actions =
      if manual do
        quote do
          actions do
            read :read do
              primary? true
              manual unquote(manual)
            end
          end
        end
      else
        quote do
          actions do
            defaults [:read]

            create :create do
              primary? true
              accept [:pid, :name, :age]
            end
          end
        end
      end

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
          extensions: [AshR2RML]

        unquote(layer_dsl)

        r2rml do
          class_iri("https://ex.org/Person")
          subject_template("https://ex.org/person/{pid}")
          table_name("xl_people")

          attribute_mappings([
            {:name, "https://schema.org/name"},
            {:age, "https://schema.org/age"}
          ])
        end

        unquote(actions)

        attributes do
          attribute :pid, :string, primary_key?: true, allow_nil?: false, public?: true
          attribute :name, :string, public?: true
          attribute :age, :integer, public?: true
        end
      end
    end
  end
end
