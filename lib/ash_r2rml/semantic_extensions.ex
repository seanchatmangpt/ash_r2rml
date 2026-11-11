# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Semantic.Extensions do
  @moduledoc """
  Ontology-first extension terms carried on the semantic IR: enums, tenancy, actions,
  policies, state machines and generated UUID keys.

  All data lives in existing IR slots so profiles that do not use these terms keep
  byte-identical IR, hashes and generated output:

    * attribute `provenance`: `:enum` (`%{values: [atom], module: String.t() | nil}`), `:generated`
    * resource `provenance`: `:multitenancy`, `:state_machine`
    * `Action.input_shape` / `Policy.expression`: plain maps (see `verify/1`)

  Check modules referenced by policies are hand-written residue by design; `residue/1`
  enumerates them for the `receipts/ash-residue.json` manifest.
  """

  alias AshR2RML.Refusal
  alias AshR2RML.SemanticIR.Resource

  @module_re ~r/\A[A-Z][A-Za-z0-9_]*(\.[A-Z][A-Za-z0-9_]*)*\z/
  @ident_re ~r/\A[a-z_][a-zA-Z0-9_]*\z/
  @kinds [:create, :update, :read, :destroy]
  @arg_types ~w(string integer boolean uuid atom date decimal float utc_datetime utc_datetime_usec map)a

  def kinds, do: @kinds
  def arg_types, do: @arg_types
  def module_name?(value), do: is_binary(value) and Regex.match?(@module_re, value)

  # --- accessors -----------------------------------------------------------------------------

  def enum(%{provenance: prov}) when is_map(prov), do: Map.get(prov, :enum)
  def enum(_), do: nil

  def generated?(%{provenance: prov}) when is_map(prov), do: Map.get(prov, :generated) == true
  def generated?(_), do: false

  def multitenancy(%Resource{provenance: prov}), do: Map.get(prov, :multitenancy)
  def state_machine(%Resource{provenance: prov}), do: Map.get(prov, :state_machine)

  @doc "Elixir module name (string) of the Ash.Type.Enum for `attribute`, or nil."
  def enum_module(%Resource{module: module}, attribute) do
    case enum(attribute) do
      nil ->
        nil

      enum ->
        enum[:module] || module_string(module) <> "." <> Macro.camelize(to_string(attribute.name))
    end
  end

  @doc "All enum modules of the resource as `{module_string, values}`."
  def enum_modules(%Resource{} = resource) do
    for attribute <- resource.attributes,
        enum(attribute),
        do: {enum_module(resource, attribute), enum(attribute).values}
  end

  def states(%{initial: initial} = sm) do
    terminal = Map.get(sm, :terminal, [])
    transitions = Map.get(sm, :transitions, [])
    all = Enum.uniq([initial | Enum.flat_map(transitions, &(List.wrap(&1.from) ++ [&1.to]))])
    intermediate = all -- [initial | terminal]
    Enum.uniq([initial | intermediate] ++ (all -- [initial | intermediate]))
  end

  @doc "Groups state-machine transitions by action: `[{action, from_states, to_state}]`."
  def transition_actions(nil), do: []

  def transition_actions(sm) do
    sm.transitions
    |> Enum.group_by(& &1.action)
    |> Enum.sort_by(&to_string(elem(&1, 0)))
    |> Enum.map(fn {action, ts} ->
      {action, ts |> Enum.flat_map(&List.wrap(&1.from)) |> Enum.uniq(), hd(ts).to}
    end)
  end

  @doc "Hand-written check modules referenced by the resource's policies."
  def residue(%Resource{} = resource) do
    for policy <- resource.policies,
        expr = policy.expression,
        is_map(expr),
        {role, mod} <- roles(expr) do
      %{module: mod, resource: module_string(resource.module), policy: to_string(policy.name), role: role}
    end
  end

  defp roles(expr) do
    Enum.map(List.wrap(expr[:authorize_if]), &{"authorize_if", &1}) ++
      Enum.map(List.wrap(expr[:forbid_if]), &{"forbid_if", &1}) ++
      if(expr[:bypass_actor], do: [{"bypass_actor", expr[:bypass_actor]}], else: [])
  end

  # --- derivation ----------------------------------------------------------------------------

  @doc "A state machine's state attribute becomes an enum over its states unless it already is one."
  def derive(%Resource{} = resource) do
    case state_machine(resource) do
      nil ->
        resource

      sm ->
        attributes =
          Enum.map(resource.attributes, fn
            %{name: name, provenance: prov} = attribute when name == sm.attribute and is_map(prov) ->
              if Map.has_key?(prov, :enum),
                do: attribute,
                else: %{attribute | provenance: Map.put(prov, :enum, %{values: states(sm), module: nil})}

            attribute ->
              attribute
          end)

        %{resource | attributes: attributes}
    end
  end

  # --- verification --------------------------------------------------------------------------

  @spec verify(Resource.t()) :: [Refusal.t()]
  def verify(%Resource{} = resource) do
    verify_enums(resource) ++
      verify_generated(resource) ++
      verify_multitenancy(resource) ++
      verify_actions(resource) ++
      verify_policies(resource) ++
      verify_state_machine(resource)
  end

  defp refuse(resource, subject, detail, evidence \\ %{}),
    do: Refusal.new(:REFUSED_UNPROVEN_EQUIVALENCE, {resource.module, subject}, detail, evidence)

  defp attr_names(resource), do: Enum.map(resource.attributes, & &1.name)

  defp verify_enums(resource) do
    Enum.flat_map(resource.attributes, fn attribute ->
      case enum(attribute) do
        nil ->
          []

        %{values: values} = enum ->
          cond do
            not is_list(values) or values == [] ->
              [refuse(resource, attribute.name, "sh:in must list at least one value", %{})]

            Enum.any?(values, &(not is_atom(&1) or not Regex.match?(@ident_re, Atom.to_string(&1)))) ->
              [refuse(resource, attribute.name, "sh:in values must be bounded identifier literals", %{values: values})]

            Enum.uniq(values) != values ->
              [refuse(resource, attribute.name, "sh:in values must be unique", %{values: values})]

            enum[:module] != nil and not module_name?(enum[:module]) ->
              [refuse(resource, attribute.name, "r2ml:enumModule must be a valid Elixir module name", %{})]

            attribute.ash_type not in [:string, nil] ->
              [
                refuse(resource, attribute.name, "sh:in requires a string-typed attribute", %{
                  ash_type: attribute.ash_type
                })
              ]

            true ->
              []
          end
      end
    end)
  end

  defp verify_generated(resource) do
    key_names = resource.identities |> Enum.flat_map(& &1.keys)

    for attribute <- resource.attributes,
        generated?(attribute),
        attribute.name not in key_names or attribute.ash_type != :uuid do
      refuse(resource, attribute.name, "r2ml:generated requires an identity key attribute with r2ml:ashType \"uuid\"")
    end
  end

  defp verify_multitenancy(resource) do
    case multitenancy(resource) do
      nil ->
        []

      %{strategy: strategy} = mt ->
        attribute = Enum.find(resource.attributes, &(&1.name == mt[:attribute]))

        cond do
          strategy not in [:attribute, :context] ->
            [
              refuse(resource, :multitenancy, "r2ml:tenantStrategy must be \"attribute\" or \"context\"", %{
                got: strategy
              })
            ]

          not is_boolean(mt[:global?]) ->
            [refuse(resource, :multitenancy, "r2ml:tenantGlobal must be boolean")]

          strategy == :attribute and is_nil(attribute) ->
            [
              refuse(resource, :multitenancy, "r2ml:tenantAttribute must name a declared attribute", %{
                attribute: mt[:attribute]
              })
            ]

          strategy == :attribute and attribute.nullable ->
            [
              refuse(resource, :multitenancy, "tenant attribute must be required (sh:minCount 1)", %{
                attribute: attribute.name
              })
            ]

          true ->
            []
        end
    end
  end

  defp verify_actions(resource) do
    actions = resource.actions
    names = attr_names(resource)

    dup =
      actions |> Enum.map(& &1.name) |> Enum.frequencies() |> Enum.filter(&(elem(&1, 1) > 1)) |> Enum.map(&elem(&1, 0))

    primaries = actions |> Enum.filter(&(shape(&1)[:primary?] == true)) |> Enum.frequencies_by(& &1.kind)

    per_action =
      Enum.flat_map(actions, fn action ->
        shape = shape(action)
        accept = shape[:accept]

        cond do
          not is_atom(action.name) or is_nil(action.name) or not Regex.match?(@ident_re, to_string(action.name)) ->
            [refuse(resource, action.name, "r2ml:actionName must be a bounded identifier")]

          action.kind not in @kinds ->
            [refuse(resource, action.name, "r2ml:actionKind must be create|update|read|destroy", %{kind: action.kind})]

          is_list(accept) and Enum.any?(accept, &(&1 not in names)) ->
            [
              refuse(resource, action.name, "r2ml:accept names an undeclared attribute", %{
                undeclared: Enum.reject(accept, &(&1 in names))
              })
            ]

          Enum.any?(shape[:arguments] || [], &(&1.type not in @arg_types or not is_atom(&1.name))) ->
            [refuse(resource, action.name, "r2ml:argument has unsupported name or type")]

          true ->
            []
        end
      end)

    if(dup == [], do: [], else: [refuse(resource, :actions, "duplicate action names", %{names: dup})]) ++
      case Enum.filter(primaries, &(elem(&1, 1) > 1)) do
        [] -> []
        many -> [refuse(resource, :actions, "more than one primary action of a kind", %{kinds: Keyword.keys(many)})]
      end ++ per_action
  end

  defp shape(%{input_shape: shape}) when is_map(shape), do: shape
  defp shape(_), do: %{}

  defp verify_policies(resource) do
    dup =
      resource.policies
      |> Enum.map(& &1.name)
      |> Enum.frequencies()
      |> Enum.filter(&(elem(&1, 1) > 1))
      |> Enum.map(&elem(&1, 0))

    if(dup == [], do: [], else: [refuse(resource, :policies, "duplicate policy names", %{names: dup})]) ++
      Enum.flat_map(resource.policies, fn policy ->
        expr = policy.expression

        cond do
          is_nil(expr) ->
            []

          not is_map(expr) ->
            [refuse(resource, policy.name, "policy requires a structured expression")]

          expr[:action_type] not in @kinds ->
            [refuse(resource, policy.name, "r2ml:actionType must be read|create|update|destroy")]

          List.wrap(expr[:authorize_if]) ++ List.wrap(expr[:forbid_if]) == [] ->
            [refuse(resource, policy.name, "policy needs r2ml:authorizeIf or r2ml:forbidIf")]

          bad = Enum.find(roles(expr), fn {_role, mod} -> not module_name?(mod) end) ->
            [
              refuse(resource, policy.name, "policy check must be a module-name string, never an expression", %{
                value: inspect(elem(bad, 1))
              })
            ]

          true ->
            []
        end
      end)
  end

  defp verify_state_machine(resource) do
    case state_machine(resource) do
      nil ->
        []

      sm ->
        attribute = Enum.find(resource.attributes, &(&1.name == sm.attribute))
        states = states(sm)
        declared_actions = Map.new(resource.actions, &{&1.name, &1})

        cond do
          is_nil(attribute) ->
            [
              refuse(resource, :state_machine, "r2ml:stateAttribute must name a declared attribute", %{
                attribute: sm.attribute
              })
            ]

          attribute.nullable ->
            [refuse(resource, :state_machine, "state attribute must be required (sh:minCount 1)")]

          sm.transitions == [] ->
            [refuse(resource, :state_machine, "state machine needs at least one transition")]

          true ->
            enum_values = (enum(attribute) || %{values: states}).values
            undeclared = states -- enum_values
            unused = enum_values -- states

            from_states = sm.transitions |> Enum.flat_map(&List.wrap(&1.from)) |> Enum.uniq()
            terminal = sm[:terminal] || []
            dead_ends = states |> Enum.reject(&(&1 in from_states or &1 in terminal))

            targets =
              sm.transitions
              |> Enum.group_by(& &1.action, & &1.to)
              |> Enum.filter(fn {_a, tos} -> length(Enum.uniq(tos)) > 1 end)
              |> Enum.map(&elem(&1, 0))

            collisions =
              for {action, _from, _to} <- transition_actions(sm),
                  declared = declared_actions[action],
                  declared.kind != :update,
                  do: action

            List.flatten([
              if(undeclared == [],
                do: [],
                else: [
                  refuse(resource, :state_machine, "transition references undeclared state", %{states: undeclared})
                ]
              ),
              if(unused == [],
                do: [],
                else: [refuse(resource, :state_machine, "enum value is not a state of the machine", %{states: unused})]
              ),
              if(dead_ends == [],
                do: [],
                else: [
                  refuse(
                    resource,
                    :state_machine,
                    "dead-end non-terminal state (declare r2ml:terminal or add a transition)",
                    %{
                      states: dead_ends
                    }
                  )
                ]
              ),
              if(targets == [],
                do: [],
                else: [
                  refuse(resource, :state_machine, "action reused with different target states", %{actions: targets})
                ]
              ),
              if(collisions == [],
                do: [],
                else: [
                  refuse(resource, :state_machine, "transition action collides with a non-update action", %{
                    actions: collisions
                  })
                ]
              )
            ])
        end
    end
  end

  # --- rendering -----------------------------------------------------------------------------

  def render_enum_module(name, values, header) do
    header <>
      "defmodule #{name} do\n  use Ash.Type.Enum, values: #{inspect(values)}\nend"
  end

  def render_multitenancy(resource) do
    case multitenancy(resource) do
      nil ->
        ""

      mt ->
        attribute = if mt[:attribute], do: "    attribute #{inspect(mt.attribute)}\n", else: ""

        "  multitenancy do\n    strategy #{inspect(mt.strategy)}\n#{attribute}    global? #{inspect(mt.global?)}\n  end\n\n"
    end
  end

  def render_state_machine(resource) do
    case state_machine(resource) do
      nil ->
        ""

      sm ->
        transitions =
          Enum.map_join(transition_actions(sm), "\n", fn {action, from, to} ->
            "      transition #{inspect(action)}, from: #{inspect(from)}, to: #{inspect(to)}"
          end)

        "  state_machine do\n    initial_states [#{inspect(sm.initial)}]\n    default_initial_state #{inspect(sm.initial)}\n" <>
          "    state_attribute #{inspect(sm.attribute)}\n\n    transitions do\n#{transitions}\n    end\n  end\n\n"
    end
  end

  def render_actions(resource) do
    sm = state_machine(resource)
    transitions = Map.new(transition_actions(sm), fn {a, _f, to} -> {a, to} end)
    declared = resource.actions
    declared_names = Enum.map(declared, & &1.name)

    generated =
      for {action, _from, to} <- transition_actions(sm), action not in declared_names do
        "    update #{inspect(action)} do\n      accept []\n      change transition_state(#{inspect(to)})\n    end"
      end

    kinds = Enum.uniq(Enum.map(declared, & &1.kind) ++ if(generated == [], do: [], else: [:update]))
    defaults = [:read, :create, :update, :destroy] -- kinds

    defaults_line = if defaults == [], do: [], else: ["    defaults #{inspect(defaults)}"]
    rendered = Enum.map(declared, &render_action(&1, transitions[&1.name]))

    "  actions do\n" <> Enum.join(defaults_line ++ rendered ++ generated, "\n\n") <> "\n  end"
  end

  defp render_action(action, transition_to) do
    shape = shape(action)

    lines =
      [
        if(shape[:primary?] == true, do: "      primary? true"),
        if(is_list(shape[:accept]) and action.kind in [:create, :update],
          do: "      accept #{inspect(shape[:accept])}"
        )
      ] ++
        Enum.map(shape[:arguments] || [], fn arg ->
          "      argument #{inspect(arg.name)}, #{inspect(arg.type)}, allow_nil?: #{inspect(arg.allow_nil?)}"
        end) ++
        [if(transition_to && action.kind == :update, do: "      change transition_state(#{inspect(transition_to)})")]

    "    #{action.kind} #{inspect(action.name)} do\n" <>
      (lines |> Enum.reject(&is_nil/1) |> Enum.join("\n")) <> "\n    end"
  end

  def render_policies(%Resource{policies: []}), do: ""

  def render_policies(resource) do
    renderable = Enum.filter(resource.policies, &is_map(&1.expression))

    if renderable == [] do
      ""
    else
      body =
        Enum.map_join(renderable, "\n\n", fn policy ->
          expr = policy.expression
          action_type = "action_type(#{inspect(expr.action_type)})"

          bypass =
            if expr[:bypass_actor],
              do: "    bypass [#{action_type}, #{expr.bypass_actor}] do\n      authorize_if always()\n    end\n\n",
              else: ""

          forbids = Enum.map(List.wrap(expr[:forbid_if]), &"      forbid_if #{&1}")
          authorizes = Enum.map(List.wrap(expr[:authorize_if]), &"      authorize_if #{&1}")

          bypass <>
            "    policy #{action_type} do\n      description #{inspect(to_string(policy.name))}\n" <>
            Enum.join(forbids ++ authorizes, "\n") <> "\n    end"
        end)

      "  policies do\n#{body}\n  end\n\n"
    end
  end

  defp module_string(module) when is_atom(module), do: inspect(module)
  defp module_string(module) when is_binary(module), do: module
end
