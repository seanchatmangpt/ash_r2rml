# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW11TypedCoverageTest do
  @moduledoc """
  Data types with no coverage on any layer (binary-safe strings, atom/enum, ci_string, map,
  array-of-string, float, large integers) round-trip through `AshR2RML.OBDA.query/3` on real ETS
  and real SQLite rows. Each type yields either the typed literal of its registry datatype or a
  typed `UNSUPPORTED_ASH_TYPE` refusal; both are recorded per type, nothing is stringified
  implicitly.
  """
  use ExUnit.Case, async: false

  alias AshR2RML.Datatype.Registry
  alias AshR2RML.DataLayerContract, as: C
  alias AshR2RML.Mapping.{LogicalTable, ObjectMap, PredicateObjectMap, SubjectMap}

  @value "http://schema.org/value"
  @row "http://schema.org/row-r1"
  @text "tab\tnl\nquote\"é☃ <&> back\\slash"
  @big 9_007_199_254_740_993

  # attribute -> {ash type as the resource declares it, stored value, expected lexical or :any}
  @cases [
    str: {Ash.Type.String, @text, @text},
    kind: {Ash.Type.Atom, :open, "open"},
    ci: {Ash.Type.CiString, "MiXed", "MiXed"},
    meta: {Ash.Type.Map, %{"k" => "v"}, :any},
    tags: {{:array, Ash.Type.String}, ["a", "b"], :any},
    ratio: {Ash.Type.Float, 0.1, :float},
    big: {Ash.Type.Integer, @big, Integer.to_string(@big)}
  ]

  defmodule EtsDom do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.RefactorW11TypedCoverageTest.EtsRow
    end
  end

  defmodule EtsRow do
    use Ash.Resource, domain: AshR2RML.RefactorW11TypedCoverageTest.EtsDom, data_layer: Ash.DataLayer.Ets

    ets do
      private? false
    end

    actions do
      defaults [:read, :destroy]

      create :create do
        primary? true
        accept [:rid, :str, :kind, :ci, :meta, :tags, :ratio, :big]
      end
    end

    attributes do
      attribute :rid, :string, primary_key?: true, allow_nil?: false, public?: true
      attribute :str, :string, public?: true
      attribute :kind, :atom, constraints: [one_of: [:open, :closed]], public?: true
      attribute :ci, :ci_string, public?: true
      attribute :meta, :map, public?: true
      attribute :tags, {:array, :string}, public?: true
      attribute :ratio, :float, public?: true
      attribute :big, :integer, public?: true
    end
  end

  if Code.ensure_loaded?(AshSqlite.DataLayer) do
    defmodule SqliteDom do
      use Ash.Domain, validate_config_inclusion?: false

      resources do
        resource AshR2RML.RefactorW11TypedCoverageTest.SqliteRow
      end
    end

    defmodule SqliteRow do
      use Ash.Resource,
        domain: AshR2RML.RefactorW11TypedCoverageTest.SqliteDom,
        data_layer: AshSqlite.DataLayer

      sqlite do
        table "w11_typed_rows"
        repo(AshR2RML.DataLayerContract.SqliteRepo)
      end

      actions do
        defaults [:read, :destroy]

        create :create do
          primary? true
          accept [:rid, :str, :kind, :ci, :meta, :tags, :ratio, :big]
        end
      end

      attributes do
        attribute :rid, :string, primary_key?: true, allow_nil?: false, public?: true
        attribute :str, :string, public?: true
        attribute :kind, :atom, constraints: [one_of: [:open, :closed]], public?: true
        attribute :ci, :ci_string, public?: true
        attribute :meta, :map, public?: true
        attribute :tags, {:array, :string}, public?: true
        attribute :ratio, :float, public?: true
        attribute :big, :integer, public?: true
      end
    end
  end

  @ddl "CREATE TABLE IF NOT EXISTS w11_typed_rows (rid TEXT PRIMARY KEY NOT NULL, str TEXT, kind TEXT, " <>
         "ci TEXT, meta TEXT, tags TEXT, ratio REAL, big INTEGER)"

  defp seed!(resource, domain) do
    attrs = Map.new(@cases, fn {name, {_type, value, _lex}} -> {name, value} end)

    resource
    |> Ash.Changeset.for_create(:create, Map.put(attrs, :rid, "r1"), domain: domain)
    |> Ash.create!(domain: domain, authorize?: false)
  end

  defp mapping(resource, attribute, datatype) do
    %AshR2RML.Mapping.Resource{
      ash_resource: resource,
      logical_table: %LogicalTable{table_name: Atom.to_string(resource)},
      subject_map: %SubjectMap{strategy: :template, value: "http://schema.org/row-{rid}"},
      class_iris: ["http://schema.org/Thing"],
      predicate_object_maps: [
        %PredicateObjectMap{
          attribute: attribute,
          predicate_iri: @value,
          object_map: %ObjectMap{strategy: :column, value: Atom.to_string(attribute), datatype: datatype}
        }
      ],
      reference_object_maps: [],
      identities: [[:rid]],
      metadata: %{attribute_columns: %{rid: "rid", "#{attribute}": Atom.to_string(attribute)}}
    }
  end

  defp observe(resource, domain, attribute, datatype) do
    sparql = "SELECT ?s ?v WHERE { ?s <#{@value}> ?v }"
    opts = [domain: domain, authorize?: false, allow_unauthorized: true]

    case AshR2RML.OBDA.query([{resource, mapping(resource, attribute, datatype)}], sparql, opts) do
      {:ok, result} -> {:ok, Enum.map(result.bindings, &Map.new(&1, fn {k, v} -> {k, C.typed_value(v)} end))}
      {:error, %{code: code}} -> {:error, code}
    end
  end

  defp assert_typed_round_trip(resource, domain) do
    seed!(resource, domain)

    for {attribute, {type, _value, lexical}} <- @cases do
      case Registry.resolve(type) do
        {:error, refusal} ->
          # No admitted literal contract: the refusal is typed and no mapping is ever built.
          assert refusal.code == :UNSUPPORTED_ASH_TYPE, "#{attribute}: #{inspect(refusal.code)}"

        {:ok, datatype} ->
          assert {:ok, [row]} = observe(resource, domain, attribute, datatype),
                 "#{attribute} did not round-trip"

          assert row["s"] == {:native, inspect(@row)}

          case row["v"] do
            {:literal, iri, lex, nil} ->
              assert iri == datatype.rdf_datatype
              assert_lexical(attribute, lexical, lex)

            {:native, repr} when is_binary(lexical) ->
              assert repr in [inspect(lexical), lexical], "#{attribute}: #{repr}"

            {:native, repr} ->
              assert repr != "", "#{attribute}: #{inspect(row["v"])}"
          end
      end
    end

    # positive control: the unconditionally supported scalars really are admitted
    for type <- [Ash.Type.String, Ash.Type.Integer, Ash.Type.Float] do
      assert {:ok, _} = Registry.resolve(type)
    end

    assert {:error, %{code: :UNSUPPORTED_ASH_TYPE}} = Registry.resolve({:array, Ash.Type.String})
  end

  defp assert_lexical(_attribute, :any, _lex), do: :ok

  defp assert_lexical(attribute, :float, lex) do
    assert {parsed, ""} = Float.parse(lex), "#{attribute}: #{lex}"
    assert parsed == 0.1
  end

  defp assert_lexical(attribute, expected, lex), do: assert(lex == expected, "#{attribute}: #{inspect(lex)}")

  test "ETS: binary-safe string, atom, ci_string, map, array, float, large integer" do
    assert_typed_round_trip(__MODULE__.EtsRow, __MODULE__.EtsDom)
  end

  if Code.ensure_loaded?(AshSqlite.DataLayer) do
    @tag :sqlite
    test "SQLite: binary-safe string, atom, ci_string, map, array, float, large integer" do
      repo = AshR2RML.DataLayerContract.Db.start_sqlite!()
      Ecto.Adapters.SQL.query!(repo, @ddl, [])

      assert_typed_round_trip(__MODULE__.SqliteRow, __MODULE__.SqliteDom)
    end
  end
end
