# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.DomainCompileTest.Domain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshR2RML.DomainCompileTest.Person
    resource AshR2RML.DomainCompileTest.Org
    resource AshR2RML.DomainCompileTest.Plain
  end
end

defmodule AshR2RML.DomainCompileTest.EmptyDomain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshR2RML.DomainCompileTest.Plain2
  end
end

defmodule AshR2RML.DomainCompileTest.Person do
  @moduledoc false
  use Ash.Resource,
    domain: AshR2RML.DomainCompileTest.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML]

  r2rml do
    class_iri("https://schema.org/Person")
    subject_template("https://schema.org/Person/{id}")
    table_name("dc_people")
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

defmodule AshR2RML.DomainCompileTest.Org do
  @moduledoc false
  use Ash.Resource,
    domain: AshR2RML.DomainCompileTest.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML]

  r2rml do
    class_iri("https://schema.org/Organization")
    subject_template("https://schema.org/Organization/{id}")
    table_name("dc_orgs")
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

defmodule AshR2RML.DomainCompileTest.Plain do
  @moduledoc false
  use Ash.Resource,
    domain: AshR2RML.DomainCompileTest.Domain,
    data_layer: Ash.DataLayer.Ets

  actions do
    defaults [:read]
  end

  attributes do
    uuid_primary_key :id
  end
end

defmodule AshR2RML.DomainCompileTest.Plain2 do
  @moduledoc false
  use Ash.Resource,
    domain: AshR2RML.DomainCompileTest.EmptyDomain,
    data_layer: Ash.DataLayer.Ets

  actions do
    defaults [:read]
  end

  attributes do
    uuid_primary_key :id
  end
end

defmodule AshR2RML.DomainCompileTest do
  use ExUnit.Case, async: true

  alias AshR2RML.DomainCompileTest.{Domain, EmptyDomain, Org, Person}

  defp modules(bundle), do: bundle.resources |> Enum.map(& &1.ash_resource) |> Enum.sort()

  test "domain_resources returns only extension-carrying resources" do
    assert Enum.sort(AshR2RML.Resource.Info.domain_resources(Domain)) == Enum.sort([Person, Org])
  end

  test "a domain compiles to a bundle of exactly its mapped resources" do
    assert {:ok, bundle} = AshR2RML.Compiler.compile(Domain)
    assert modules(bundle) == Enum.sort([Person, Org])
  end

  test "mixed domain/resource list dedupes" do
    assert {:ok, bundle} = AshR2RML.Compiler.compile([Domain, Person])
    assert modules(bundle) == Enum.sort([Person, Org])
  end

  test "domain without mapped resources is refused naming the domain" do
    assert {:error, %AshR2RML.Refusal{code: :REFUSED_MISSING_SUBJECT_MAP, detail: detail}} =
             AshR2RML.Compiler.compile(EmptyDomain)

    assert detail =~ inspect(EmptyDomain)
  end
end
