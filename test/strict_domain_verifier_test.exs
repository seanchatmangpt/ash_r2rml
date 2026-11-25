# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.StrictDomainVerifierTest.Fixtures do
  @moduledoc false

  defmodule Good do
    @moduledoc false
    use Ash.Resource, domain: nil, data_layer: Ash.DataLayer.Ets, extensions: [AshR2RML.Resource]

    ets do
      private?(false)
    end

    attributes do
      uuid_primary_key :id
      attribute :name, :string, public?: true
    end

    r2rml do
      table_name("strict_good")
      class("http://xmlns.com/foaf/0.1/Person")

      subject do
        template("urn:uuid:{id}")
      end

      property(:name, "http://xmlns.com/foaf/0.1/name")
      graph("urn:uuid:00000000-0000-0000-0000-0000000000a1")
    end
  end

  defmodule Blank do
    @moduledoc false
    use Ash.Resource, domain: nil, data_layer: Ash.DataLayer.Ets, extensions: [AshR2RML.Resource]

    ets do
      private?(false)
    end

    attributes do
      uuid_primary_key :id
      attribute :name, :string, public?: true
    end

    r2rml do
      table_name("strict_blank")
      class("http://xmlns.com/foaf/0.1/Person")

      subject do
        term_type(:blank_node)
      end

      property(:name, "http://xmlns.com/foaf/0.1/name")
    end
  end

  # Public IRIs, but outside the narrowed foaf + urn subset used by the refusal tests.
  defmodule OffList do
    @moduledoc false
    use Ash.Resource, domain: nil, data_layer: Ash.DataLayer.Ets, extensions: [AshR2RML.Resource]

    ets do
      private?(false)
    end

    attributes do
      uuid_primary_key :id
      attribute :name, :string, public?: true
    end

    r2rml do
      table_name("strict_offlist")
      class("https://schema.org/Person")

      subject do
        template("urn:sha256:{id}")
      end

      property(:name, "https://schema.org/name")
      graph("https://schema.org/graph/things")
    end
  end
end

defmodule AshR2RML.StrictDomainVerifierTest.LaxDomain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false, extensions: [AshR2RML.Domain]

  resources do
    resource AshR2RML.StrictDomainVerifierTest.Fixtures.OffList
  end
end

defmodule AshR2RML.StrictDomainVerifierTest.DefaultStrictDomain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false, extensions: [AshR2RML.Domain]

  r2rml_domain do
    strict? true
  end

  resources do
    resource AshR2RML.StrictDomainVerifierTest.Fixtures.Good
  end
end

defmodule AshR2RML.StrictDomainVerifierTest.CustomStrictDomain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false, extensions: [AshR2RML.Domain]

  r2rml_domain do
    strict? true

    allowed_iri_prefixes([
      "https://schema.org/",
      "urn:sha256:"
    ])
  end

  resources do
    resource AshR2RML.StrictDomainVerifierTest.Fixtures.OffList
  end
end

defmodule AshR2RML.StrictDomainVerifierTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Domain.Verifier
  alias AshR2RML.Mapping.{GraphMap, ObjectMap, PredicateObjectMap, ReferenceObjectMap, SubjectMap}
  alias AshR2RML.StrictDomainVerifierTest.Fixtures.{Blank, Good, OffList}

  @default AshR2RML.Domain.default_allowed_prefixes()

  # Narrowed public subset: foaf plus content-addressed URNs. Other public
  # namespaces (schema.org, prov, ...) must be refused against it.
  @narrow ["http://xmlns.com/foaf/0.1/", "urn:uuid:", "urn:sha256:"]

  defp mapping(resource) do
    {:ok, m} = AshR2RML.Resource.Info.mapping_result(resource)
    m
  end

  defp pom(predicate) do
    %PredicateObjectMap{
      predicate_iri: predicate,
      object_map: %ObjectMap{strategy: :column, value: "name"}
    }
  end

  defp strict(resource, m, prefixes \\ @narrow), do: Verifier.strict_check(resource, m, prefixes)

  describe "refusals against a narrowed public subset" do
    test "blank-node subject map is refused" do
      assert [msg] = strict(Blank, mapping(Blank))
      assert msg =~ "blank-node subject"
      assert msg =~ inspect(Blank)
    end

    test "a real public predicate outside the subset is refused" do
      m = %{mapping(Good) | predicate_object_maps: [pom("https://schema.org/name")]}
      assert [msg] = strict(Good, m)
      assert msg =~ "predicate IRI"
      assert msg =~ "https://schema.org/name"
    end

    test "a real public class outside the subset is refused" do
      m = %{mapping(Good) | class_iris: ["https://schema.org/Thing"]}
      assert [msg] = strict(Good, m)
      assert msg =~ "class IRI"
      assert msg =~ "https://schema.org/Thing"
    end

    test "reference predicate outside the subset is refused" do
      ref = %ReferenceObjectMap{predicate_iri: "https://schema.org/knows", parent_resource: Good}
      m = %{mapping(Good) | reference_object_maps: [ref]}
      assert [msg] = strict(Good, m)
      assert msg =~ "https://schema.org/knows"
    end

    test "constant graph IRI outside the subset is refused" do
      m = %{mapping(Good) | graph_maps: [%GraphMap{strategy: :constant, value: "http://www.w3.org/ns/prov#g"}]}
      assert [msg] = strict(Good, m)
      assert msg =~ "graph IRI"
      assert msg =~ "http://www.w3.org/ns/prov#g"
    end

    test "template graph is judged by its literal prefix" do
      bad = %GraphMap{strategy: :template, value: "https://schema.org/g/{id}"}
      good = %GraphMap{strategy: :template, value: "urn:uuid:{id}"}
      assert [_] = strict(Good, %{mapping(Good) | graph_maps: [bad]})
      assert [] == strict(Good, %{mapping(Good) | graph_maps: [good]})
    end

    test "every violation is reported, not just the first" do
      m = %{
        mapping(Blank)
        | class_iris: ["https://schema.org/C"],
          predicate_object_maps: [pom("https://schema.org/p")]
      }

      assert length(strict(Blank, m)) == 3
    end

    test "off-list fixture resource is refused against the narrowed subset" do
      msgs = strict(OffList, mapping(OffList))
      assert Enum.any?(msgs, &(&1 =~ "class IRI"))
      assert Enum.any?(msgs, &(&1 =~ "predicate IRI"))
      assert Enum.any?(msgs, &(&1 =~ "graph IRI"))
    end

    test "template subject is judged by its literal prefix" do
      outside = %SubjectMap{strategy: :template, value: "https://schema.org/Person/{id}", term_type: :iri}
      assert [msg] = strict(Good, %{mapping(Good) | subject_map: outside})
      assert msg =~ "subject IRI"

      inside = %SubjectMap{strategy: :template, value: "urn:uuid:{id}", term_type: :iri}
      assert [] == strict(Good, %{mapping(Good) | subject_map: inside})

      placeholder_first = %SubjectMap{strategy: :template, value: "{id}", term_type: :iri}
      assert [_] = strict(Good, %{mapping(Good) | subject_map: placeholder_first})
    end
  end

  describe "hardening" do
    defp with_class(iri), do: %{mapping(Good) | class_iris: [iri]}

    test "prefix confusion: sibling host, userinfo and case are refused" do
      for iri <- [
            "https:/schema.org/Thing",
            "https:schema.org/Thing",
            "https://schema.org" <> "%2FThing",
            "HTTPS://schema.org/Thing",
            String.replace("https://schema.org/Thing", "//", "///")
          ] do
        assert [_] = strict(Good, with_class(iri), @default), "#{iri} was admitted"
      end
    end

    test "user prefixes without a delimiter are refused" do
      assert [msg] = Verifier.validate_prefixes(["https://schema.org"])
      assert msg =~ "must end in"
      assert length(Verifier.validate_prefixes(["", "https://schema.org/ok/", "x", 5])) == 3
      assert [_] = Verifier.validate_prefixes("not a list")
      assert [] == Verifier.validate_prefixes(["https://schema.org/", "http://www.w3.org/ns/prov#"])
      assert [] == Verifier.validate_prefixes(@default)
    end

    test "template graph starting with a placeholder is refused" do
      g = %GraphMap{strategy: :template, value: "{graph}/x"}
      assert [msg] = strict(Good, %{mapping(Good) | graph_maps: [g]}, @default)
      assert msg =~ "graph IRI"
    end

    test "template graph without delimiter before placeholder is refused" do
      g = %GraphMap{strategy: :template, value: "http://xmlns.com/foaf/0.1" <> "{x}"}
      assert [_] = strict(Good, %{mapping(Good) | graph_maps: [g]}, @default)
    end

    test "constant object-map IRI is checked" do
      om = %ObjectMap{strategy: :constant, value: "https:/schema.org/o", term_type: :iri}
      pom = %PredicateObjectMap{predicate_iri: "https://schema.org/knows", object_map: om}
      assert [msg] = strict(Good, %{mapping(Good) | predicate_object_maps: [pom]}, @default)
      assert msg =~ "object IRI"

      lit = %ObjectMap{strategy: :constant, value: "plain literal"}
      pom2 = %PredicateObjectMap{predicate_iri: "https://schema.org/name", object_map: lit}
      assert [] == strict(Good, %{mapping(Good) | predicate_object_maps: [pom2]}, @default)
    end

    test "constant subject IRI is checked" do
      sm = %SubjectMap{strategy: :constant, value: "https:/schema.org/s"}
      assert [msg] = strict(Good, %{mapping(Good) | subject_map: sm}, @default)
      assert msg =~ "subject IRI"
    end

    test "errors are sorted and deterministic" do
      m = %{
        mapping(Blank)
        | class_iris: ["https:/schema.org/Z", "https:/schema.org/A"],
          predicate_object_maps: [pom("https:/schema.org/m")]
      }

      msgs = strict(Blank, m, @default)
      assert msgs == Enum.sort(msgs)
      assert msgs == strict(Blank, m, @default)
    end

    test "nil joins on a reference map do not crash the join check" do
      ref = %ReferenceObjectMap{predicate_iri: "https://schema.org/p", parent_resource: Good, joins: nil}
      m = %{mapping(Good) | reference_object_maps: [ref]}
      assert [] == Verifier.check(Good, m, [Good], %{Good => mapping(Good)})
    end

    test "delimiter-less allowlist entries are refused by the prefix validator" do
      assert [msg | _] = Verifier.validate_prefixes(["https://schema.org"])
      assert msg =~ "must end in"
    end
  end

  describe "acceptance" do
    test "conforming mapping passes with the default and the narrowed allowlist" do
      assert strict(Good, mapping(Good), @default) == []
      assert strict(Good, mapping(Good), @narrow) == []
    end

    test "custom allowlist accepts what the narrowed subset refuses" do
      custom = ["https://schema.org/", "urn:sha256:"]
      assert strict(OffList, mapping(OffList), custom) == []
    end

    test "default allowlist accepts public schema.org IRIs" do
      assert strict(OffList, mapping(OffList), @default) == []
    end

    test "custom allowlist replaces the default list" do
      assert [_ | _] = strict(Good, mapping(Good), ["http://www.w3.org/ns/prov#"])
    end

    test "every allowlisted prefix is accepted as class, predicate and graph" do
      for prefix <- @default do
        iri = prefix <> "Probe"

        m = %{
          mapping(Good)
          | class_iris: [iri],
            predicate_object_maps: [pom(iri)],
            graph_maps: [%GraphMap{strategy: :constant, value: iri}]
        }

        assert strict(Good, m, @default) == [], "prefix #{prefix} was refused"
      end
    end

    test "default allowlist is exactly the public set" do
      expected = [
        "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
        "http://www.w3.org/2000/01/rdf-schema#",
        "http://www.w3.org/2001/XMLSchema#",
        "http://www.w3.org/2002/07/owl#",
        "http://www.w3.org/ns/shacl#",
        "http://www.w3.org/ns/shacl-ui#",
        "http://www.w3.org/2006/time#",
        "http://www.w3.org/ns/org#",
        "http://www.w3.org/ns/odrl/2/",
        "http://xmlns.com/foaf/0.1/",
        "http://www.w3.org/2004/02/skos/core#",
        "http://www.w3.org/ns/prov#",
        "http://purl.org/net/p-plan#",
        "http://purl.org/dc/terms/",
        "https://schema.org/",
        "http://schema.org/",
        "https://spec.edmcouncil.org/fibo/ontology/FND/Accounting/CurrencyAmount/",
        "https://spec.edmcouncil.org/fibo/ontology/FBC/ProductsAndServices/ClientsAndAccounts/",
        "https://www.ocel-standard.org/",
        "urn:uuid:",
        "urn:sha256:"
      ]

      assert Enum.sort(@default) == Enum.sort(expected)
      assert length(Enum.uniq(@default)) == length(@default)
      assert Verifier.validate_prefixes(@default) == []
    end
  end

  describe "domain wiring" do
    alias AshR2RML.StrictDomainVerifierTest.{CustomStrictDomain, DefaultStrictDomain, LaxDomain}

    test "strict domain with conforming resource compiles and bundles" do
      assert {:ok, _} = AshR2RML.Compiler.compile(DefaultStrictDomain)
    end

    test "strict domain with custom allowlist compiles an off-list resource" do
      assert {:ok, _} = AshR2RML.Compiler.compile(CustomStrictDomain)
    end

    test "non-strict default domain still compiles off-list IRIs" do
      assert {:ok, _} = AshR2RML.Compiler.compile(LaxDomain)
    end

    test "strict option defaults to false and prefixes unset on a lax domain" do
      refute Spark.Dsl.Extension.get_opt(LaxDomain, [:r2rml_domain], :strict?, false)
      assert Spark.Dsl.Extension.get_opt(DefaultStrictDomain, [:r2rml_domain], :strict?, false)

      assert Spark.Dsl.Extension.get_opt(CustomStrictDomain, [:r2rml_domain], :allowed_iri_prefixes) ==
               ["https://schema.org/", "urn:sha256:"]
    end
  end
end
