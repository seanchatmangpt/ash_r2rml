# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Domain do
  @moduledoc """
  Spark extension for `Ash.Domain` that verifies the R2RML reference object maps
  of every mapped resource in the domain at compile time.

  Checks per `AshR2RML.Mapping.ReferenceObjectMap`:

    * the parent resource is a member of the domain
    * each join's parent column exists on the parent resource or mapping
    * each join's child column exists on the child resource or mapping
    * the parent has a subject map
    * the parent carries a mapping that resolves (a parent refusal is surfaced verbatim)

  Enable it on a domain with:

      use Ash.Domain, extensions: [AshR2RML.Domain]

  ## Strict mode (opt-in)

      r2rml_domain do
        strict? true
        # allowed_iri_prefixes ["http://xmlns.com/foaf/0.1/", "urn:uuid:"]   # replaces the default list
      end

  With `strict?` true, compilation fails when any subject map is a blank node
  (`term_type :blank_node` or strategy `:blank_node`), or when any class,
  predicate, graph, subject or IRI-valued object IRI (constant, or the literal prefix
  of a template) lies outside `allowed_iri_prefixes`. Every violation is reported.
  The default allowlist is `default_allowed_prefixes/0`: public ontologies only
  (rdf, rdfs, xsd, owl, sh, shui, time, org, odrl, foaf, skos, prov, p-plan, dcterms,
  schema, fibo-fnd-acc-cur, fibo-fbc-pas-caa, ocel) plus `urn:uuid:` and `urn:sha256:`.
  Non-strict domains behave exactly as before.
  """

  @default_allowed_prefixes [
    # rdf
    "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
    # rdfs
    "http://www.w3.org/2000/01/rdf-schema#",
    # xsd
    "http://www.w3.org/2001/XMLSchema#",
    # owl
    "http://www.w3.org/2002/07/owl#",
    # sh
    "http://www.w3.org/ns/shacl#",
    # shui
    "http://www.w3.org/ns/shacl-ui#",
    # time
    "http://www.w3.org/2006/time#",
    # org
    "http://www.w3.org/ns/org#",
    # odrl
    "http://www.w3.org/ns/odrl/2/",
    # foaf
    "http://xmlns.com/foaf/0.1/",
    # skos
    "http://www.w3.org/2004/02/skos/core#",
    # prov
    "http://www.w3.org/ns/prov#",
    # p-plan
    "http://purl.org/net/p-plan#",
    # dcterms
    "http://purl.org/dc/terms/",
    # schema
    "https://schema.org/",
    "http://schema.org/",
    # fibo-fnd-acc-cur
    "https://spec.edmcouncil.org/fibo/ontology/FND/Accounting/CurrencyAmount/",
    # fibo-fbc-pas-caa
    "https://spec.edmcouncil.org/fibo/ontology/FBC/ProductsAndServices/ClientsAndAccounts/",
    # ocel
    "https://www.ocel-standard.org/",
    # content-addressed URNs
    "urn:uuid:",
    "urn:sha256:"
  ]

  @doc "Default public-only namespace allowlist used by strict mode."
  @spec default_allowed_prefixes() :: [String.t()]
  def default_allowed_prefixes, do: @default_allowed_prefixes

  @r2rml_domain %Spark.Dsl.Section{
    name: :r2rml_domain,
    describe: "Opt-in strict verification of the domain's R2RML mappings.",
    schema: [
      strict?: [
        type: :boolean,
        default: false,
        doc: "Reject blank-node subject maps and non-allowlisted class/predicate/graph IRIs."
      ],
      allowed_iri_prefixes: [
        type: {:list, :string},
        doc: "IRI prefixes permitted in strict mode. Defaults to `default_allowed_prefixes/0`."
      ]
    ]
  }

  use Spark.Dsl.Extension,
    sections: [@r2rml_domain],
    verifiers: [AshR2RML.Domain.Verifier]
end
