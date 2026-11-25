# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Red2PersistOrdering.AddAttribute do
  @moduledoc false
  use Spark.Dsl.Transformer

  @impl true
  def transform(dsl) do
    Ash.Resource.Builder.add_new_attribute(dsl, :extra, :string,
      source: :extra_col,
      public?: true
    )
  end
end

defmodule AshR2RML.Red2PersistOrdering.AddRelationship do
  @moduledoc false
  use Spark.Dsl.Transformer

  @impl true
  def transform(dsl) do
    Ash.Resource.Builder.add_new_relationship(
      dsl,
      :belongs_to,
      :owner,
      AshR2RML.Red2PersistOrdering.Owner,
      source_attribute: :owner_ref,
      define_attribute?: false
    )
  end
end

defmodule AshR2RML.Red2PersistOrdering.ExtAttribute do
  @moduledoc false
  use Spark.Dsl.Extension,
    transformers: [AshR2RML.Red2PersistOrdering.AddAttribute]
end

defmodule AshR2RML.Red2PersistOrdering.ExtRelationship do
  @moduledoc false
  use Spark.Dsl.Extension,
    transformers: [AshR2RML.Red2PersistOrdering.AddRelationship]
end

defmodule AshR2RML.Red2PersistOrdering.Owner do
  @moduledoc false
  use Ash.Resource,
    domain: nil,
    data_layer: Ash.DataLayer.Ets

  ets do
    private?(false)
  end

  actions do
    defaults [:read]
  end

  attributes do
    uuid_primary_key :id
  end
end

defmodule AshR2RML.Red2PersistOrderingTest do
  @moduledoc """
  A third-party Spark transformer that adds an attribute or a relationship must be
  visible to the Persist transformer, and mappings must use declared source columns.
  """
  use ExUnit.Case, async: false

  alias AshR2RML.Resource.Info

  defp compile(name, extension, body) do
    source = """
    defmodule #{name} do
      use Ash.Resource,
        domain: nil,
        data_layer: Ash.DataLayer.Ets,
        extensions: [AshR2RML.Resource, #{extension}]

      ets do
        private?(false)
      end

      r2rml do
        table_name("red2_persist_ordering")
        class("http://schema.org/Thing")
        subject(template: "urn:uuid:{id}")
        #{body}
      end

      actions do
        defaults [:read]
      end

      attributes do
        uuid_primary_key :id
        attribute :owner_ref, :uuid, source: :owner_ref_col, public?: true
      end
    end
    """

    try do
      Code.compile_string(source)
      {:ok, Module.concat([name])}
    rescue
      error -> {:error, error}
    end
  end

  test "attribute added by a third-party transformer is mapped via its declared source column" do
    body = ~s|property :extra, "https://schema.org/alternateName"|

    assert {:ok, module} =
             compile(
               "AshR2RML.Red2PersistOrdering.AttrRes",
               "AshR2RML.Red2PersistOrdering.ExtAttribute",
               body
             )

    mapping = Info.mapping!(module)
    pom = Enum.find(mapping.predicate_object_maps, &(&1.attribute == :extra))

    assert pom, "property on a transformer-added attribute must be mapped"
    assert pom.object_map.value == "extra_col"
  end

  test "relationship added by a third-party transformer joins on the source column, not the name" do
    body = ~s|reference :owner, "https://schema.org/owner"|

    assert {:ok, module} =
             compile(
               "AshR2RML.Red2PersistOrdering.RelRes",
               "AshR2RML.Red2PersistOrdering.ExtRelationship",
               body
             )

    mapping = Info.mapping!(module)
    ref = Enum.find(mapping.reference_object_maps, &(&1.relationship == :owner))

    assert ref, "reference on a transformer-added relationship must be mapped"
    assert [%{child: "owner_ref_col", parent: "id"}] = ref.joins
  end
end
