# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.DomainVerifierTest.Domain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false, extensions: [AshR2RML.Domain]

  resources do
    resource AshR2RML.DomainVerifierTest.Org
    resource AshR2RML.DomainVerifierTest.Member
  end
end

defmodule AshR2RML.DomainVerifierTest.Org do
  @moduledoc false
  use Ash.Resource,
    domain: AshR2RML.DomainVerifierTest.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML]

  r2rml do
    class_iri("https://schema.org/Organization")
    subject_template("https://schema.org/Organization/{id}")
    table_name("dv_orgs")
    attribute_mappings([{:name, "https://schema.org/name"}])
  end

  actions do
    defaults [:read]
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end
end

defmodule AshR2RML.DomainVerifierTest.Member do
  @moduledoc false
  use Ash.Resource,
    domain: AshR2RML.DomainVerifierTest.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML]

  r2rml do
    class_iri("https://schema.org/Person")
    subject_template("https://schema.org/Person/{id}")
    table_name("dv_members")
    attribute_mappings([{:name, "https://schema.org/name"}])
    relationship_mappings([{:organization, "https://schema.org/memberOf"}])
  end

  actions do
    defaults [:read]
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end

  relationships do
    belongs_to :organization, AshR2RML.DomainVerifierTest.Org, public?: true
  end
end

defmodule AshR2RML.DomainVerifierTest.RemapDomain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false, extensions: [AshR2RML.Domain]

  resources do
    resource AshR2RML.DomainVerifierTest.RemapParent
    resource AshR2RML.DomainVerifierTest.RemapChild
  end
end

defmodule AshR2RML.DomainVerifierTest.RemapParent do
  @moduledoc false
  use Ash.Resource,
    domain: AshR2RML.DomainVerifierTest.RemapDomain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML]

  r2rml do
    class_iri("https://schema.org/Organization")
    subject_template("https://schema.org/Organization/{id}")
    table_name("dv_remap_parents")
    attribute_mappings([{:name, "https://schema.org/name"}])
  end

  actions do
    defaults [:read]
  end

  attributes do
    uuid_primary_key :id
    attribute :code, :string, public?: true, source: :code_col
    attribute :name, :string, public?: true
  end
end

defmodule AshR2RML.DomainVerifierTest.RemapChild do
  @moduledoc false
  use Ash.Resource,
    domain: AshR2RML.DomainVerifierTest.RemapDomain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML]

  r2rml do
    class_iri("https://schema.org/Person")
    subject_template("https://schema.org/Person/{id}")
    table_name("dv_remap_children")
    attribute_mappings([{:name, "https://schema.org/name"}])
    relationship_mappings([{:parent, "https://schema.org/memberOf"}])
  end

  actions do
    defaults [:read]
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end

  relationships do
    belongs_to :parent, AshR2RML.DomainVerifierTest.RemapParent, public?: true
  end
end

defmodule AshR2RML.DomainVerifierTest do
  use ExUnit.Case, async: true

  alias AshR2RML.DomainVerifierTest.{RemapChild, RemapParent}
  alias AshR2RML.Refusal

  alias AshR2RML.Domain.Verifier
  alias AshR2RML.DomainVerifierTest.{Domain, Member, Org}
  alias AshR2RML.Mapping.JoinCondition

  defp mappings do
    Map.new([Org, Member], fn r ->
      {:ok, m} = AshR2RML.Resource.Info.mapping_result(r)
      {r, m}
    end)
  end

  test "extension is registered on the domain and a valid domain verifies" do
    assert AshR2RML.Domain in Spark.extensions(Domain)
    assert {:ok, _bundle} = AshR2RML.Compiler.compile(Domain)
  end

  test "valid domain yields no verifier errors" do
    maps = mappings()
    assert Verifier.check(Member, maps[Member], [Org, Member], maps) == []
  end

  test "parent outside the domain is reported" do
    maps = mappings()
    [error] = Verifier.check(Member, maps[Member], [Member], maps)
    assert error =~ "not in the domain"
    assert error =~ inspect(Org)
  end

  test "missing parent join column is reported" do
    maps = mappings()
    member = maps[Member]
    [ref] = member.reference_object_maps
    bad = %{ref | joins: [%JoinCondition{child: "organization_id", parent: "ghost_col"}]}
    member = %{member | reference_object_maps: [bad]}

    [error] = Verifier.check(Member, member, [Org, Member], maps)
    assert error =~ "ghost_col"
  end

  defp remap_check(joins, mappings_override \\ %{}) do
    maps =
      Map.new([RemapParent, RemapChild], fn r ->
        {:ok, m} = AshR2RML.Resource.Info.mapping_result(r)
        {r, m}
      end)

    child = maps[RemapChild]
    [ref] = child.reference_object_maps
    child = %{child | reference_object_maps: [%{ref | joins: joins}]}
    Verifier.check(RemapChild, child, [RemapParent, RemapChild], Map.merge(maps, mappings_override))
  end

  test "join on a remapped parent source column is accepted" do
    assert remap_check([%JoinCondition{child: "parent_id", parent: "code_col"}]) == []
  end

  test "attribute name is not a column when the attribute is remapped" do
    [error] = remap_check([%JoinCondition{child: "parent_id", parent: "code"}])
    assert error =~ "parent join column"
    assert error =~ "\"code\""
  end

  test "missing child join column is reported" do
    [error] = remap_check([%JoinCondition{child: "ghost_child", parent: "code_col"}])
    assert error =~ "child join column"
    assert error =~ "ghost_child"
  end

  test "parent's real refusal is surfaced instead of 'no mapping'" do
    refusal = Refusal.new(:REFUSED_MISSING_SUBJECT_MAP, RemapParent, "subject template unresolved")

    [error] =
      remap_check([%JoinCondition{child: "parent_id", parent: "code_col"}], %{RemapParent => refusal})

    assert error =~ "REFUSED_MISSING_SUBJECT_MAP"
    assert error =~ "subject template unresolved"
    refute error =~ "carries no R2RML mapping"
  end

  test "parent without a subject map is reported" do
    maps = mappings()
    maps = Map.update!(maps, Org, &%{&1 | subject_map: nil})
    [error] = Verifier.check(Member, maps[Member], [Org, Member], maps)
    assert error =~ "no subject map"
  end
end
