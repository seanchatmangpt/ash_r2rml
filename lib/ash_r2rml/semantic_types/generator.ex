# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.SemanticTypes.Generator do
  @moduledoc """
  Deterministic projection renderer for semantic type plans.

  It returns path/content data only. Igniter or ggen owns filesystem mutation.
  """

  alias AshR2RML.SemanticType.Plan

  @spec files(Plan.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def files(%Plan{} = plan, opts \\ []) do
    namespace = Keyword.get(opts, :namespace, "AshR2RML.Generated.SemanticTypes")

    with {:ok, manifest} <- AshR2RML.SemanticTypes.manifest_json(plan) do
      {:ok,
       %{
         "generated/catalog/semantic-types.json" => manifest <> "\n",
         "generated/ash/semantic_types.ex" => render_elixir(plan, namespace),
         "generated/test/semantic_types_contract_test.exs" => render_contract_tests(plan, namespace)
       }}
    end
  end

  @spec igniter_files(Plan.t(), atom() | String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def igniter_files(%Plan{} = plan, app_name, opts \\ []) do
    namespace = Keyword.get_lazy(opts, :namespace, fn -> app_name |> to_string() |> Macro.camelize() |> then(&("#{&1}.SemanticTypes")) end)
    app_path = app_name |> to_string() |> String.replace("-", "_")

    with {:ok, manifest} <- AshR2RML.SemanticTypes.manifest_json(plan) do
      {:ok,
       %{
         "lib/#{app_path}/semantic_types/generated.ex" => render_elixir(plan, namespace),
         "priv/semantic/semantic-types.json" => manifest <> "\n"
       }}
    end
  end

  @spec render_elixir(Plan.t(), String.t()) :: String.t()
  def render_elixir(%Plan{} = plan, namespace) do
    generated = plan.types |> Enum.filter(&(&1.selected_representation == :new_type)) |> Enum.map_join("\n\n", &render_new_type(&1, namespace))

    catalog = """
    defmodule #{namespace}.Catalog do
      @moduledoc false
      @plan_id #{inspect(plan.id)}
      @semantic_type_ids #{inspect(Enum.map(plan.types, & &1.id))}

      def plan_id, do: @plan_id
      def semantic_type_ids, do: @semantic_type_ids
    end
    """

    header = """
    # SPDX-FileCopyrightText: 2026 ash_r2rml generated projection
    #
    # SPDX-License-Identifier: MIT
    # GENERATED PROJECTION — DO NOT EDIT.
    # semantic_type_plan_id=#{plan.id}

    """

    header <> catalog <> if(generated == "", do: "", else: "\n" <> generated <> "\n")
  end

  @spec render_contract_tests(Plan.t(), String.t()) :: String.t()
  def render_contract_tests(%Plan{} = plan, namespace) do
    """
    # SPDX-FileCopyrightText: 2026 ash_r2rml generated projection
    #
    # SPDX-License-Identifier: MIT
    # GENERATED PROJECTION — DO NOT EDIT.

    defmodule #{namespace}.GeneratedContractTest do
      use ExUnit.Case, async: true

      test "generated catalog is bound to the admitted plan" do
        assert #{namespace}.Catalog.plan_id() == #{inspect(plan.id)}
        assert length(#{namespace}.Catalog.semantic_type_ids()) == #{length(plan.types)}
      end
    end
    """
  end

  defp render_new_type(type, namespace) do
    module = "#{namespace}.#{type.name |> Atom.to_string() |> Macro.camelize()}"

    """
    defmodule #{module} do
      @moduledoc false

      use Ash.Type.NewType,
        subtype_of: #{inspect(type.ash_type)},
        constraints: #{inspect(type.constraints)}

      use AshR2RML.Type,
        semantic_kind: #{inspect(type.semantic_kind)},
        datatype_iri: #{inspect(type.datatype_iri)},
        class_iri: #{inspect(type.class_iri)},
        concept_scheme_iri: #{inspect(type.concept_scheme_iri)},
        shacl_constraints: #{inspect(type.shacl_constraints)}
    end
    """
    |> String.trim()
  end
end
