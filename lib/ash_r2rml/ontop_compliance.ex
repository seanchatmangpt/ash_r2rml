# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OBDA.Ontop.Compliance do
  @moduledoc """
  Machine-readable capability contract for the pinned Ontop conformance engine.

  The profile mirrors Ontop 5.5.0's published standards-compliance surface.
  AshR2RML remains a semantic compiler: SPARQL and GeoSPARQL execution authority
  stays with Ontop and is observed through the existing read-only protocol/CLI
  boundaries.

  Source inconsistencies are preserved rather than silently corrected. For
  example, Ontop's aggregate row declares `6/6` while listing seven aggregate
  function names.
  """

  alias AshR2RML.Refusal

  @version "5.5.0"
  @source_updated "2026-07-21"
  @source_url "https://ontop-vkg.org/guide/compliance.html"

  # {section, declared coverage, supported features, unsupported features, limitations}
  @sparql [
    {"5. Graph Patterns", "2/2", ["BGP", "FILTER"], [], []},
    {"6. Including Optional Values", "1/1", ["OPTIONAL"], [], []},
    {"7. Matching Alternatives", "1/1", ["UNION"], [], []},
    {"8. Negation", "2/2", ["MINUS", "FILTER NOT EXISTS"], [], []},
    {"9. Property Paths", "5/8",
     ["PredicatePath", "InversePath", "SequencePath", "AlternativePath", "NegatedPropertySet"],
     ["ZeroOrMorePath", "OneOrMorePath", "ZeroOrOnePath"], []},
    {"10. Assignment", "2/2", ["BIND", "VALUES"], [], []},
    {"11. Aggregates", "6/6", ["COUNT", "SUM", "MIN", "MAX", "AVG", "GROUP_CONCAT", "SAMPLE"], [],
     ["Published coverage says 6/6 while the same row lists seven aggregate names."]},
    {"12. Subqueries", "1/1", ["Subqueries"], [], []},
    {"13. RDF Dataset", "2/2", ["GRAPH", "FROM NAMED"], [], []},
    {"14. Basic Federated Query", "0", [], ["SERVICE"], []},
    {"15. Solution Seqs. & Mods.", "6/6", ["ORDER BY", "SELECT", "DISTINCT", "REDUCED", "OFFSET", "LIMIT"], [], []},
    {"16. Query Forms", "4/4", ["SELECT", "CONSTRUCT", "ASK", "DESCRIBE"], [], []},
    {"17.4.1. Functional Forms", "11/11",
     ["BOUND", "IF", "COALESCE", "EXISTS", "NOT EXISTS", "||", "&&", "=", "sameTerm", "IN", "NOT IN"], [],
     ["EXISTS is limited to cases translatable bottom-up with a left join."]},
    {"17.4.2. Functions on RDF Terms", "11/13",
     ["isIRI", "isBlank", "isLiteral", "isNumeric", "str", "lang", "datatype", "IRI", "BNODE", "UUID", "STRUUID"],
     ["STRDT", "STRLANG"], []},
    {"17.4.3. Functions on Strings", "14/14",
     ["STRLEN", "SUBSTR", "UCASE", "LCASE", "STRSTARTS", "STRENDS", "CONTAINS", "STRBEFORE", "STRAFTER",
      "ENCODE_FOR_URI", "CONCAT", "langMatches", "REGEX", "REPLACE"], [],
     ["REGEX and REPLACE depend on the DBMS regex dialect.", "langMatches requires a constant second argument."]},
    {"17.4.4. Functions on Numerics", "5/5", ["abs", "round", "ceil", "floor", "RAND"], [], []},
    {"17.4.5. Functions on Dates&Times", "8/9",
     ["now", "year", "month", "day", "hours", "minutes", "seconds", "tz"], ["timezone"], []},
    {"17.4.6. Hash Functions", "5/5", ["MD5", "SHA1", "SHA256", "SHA384", "SHA512"], [],
     ["Hash-function availability depends on the DBMS."]},
    {"17.5 XPath Constructor Functions", "7/7",
     ["xsd:string", "xsd:float", "xsd:double", "xsd:decimal", "xsd:integer", "xsd:boolean", "xsd:dateTime"], [],
     ["Boolean, decimal, and dateTime casts have DB-dialect-specific normalization/validation limits."]},
    {"17.6 Extensible Value Testing", "0", [], ["user defined functions"], []}
  ]

  @geosparql [
    {"7. Topology Vocabulary Extensions - Properties", "0", [],
     ["geo:sfEquals", "geo:sfDisjoint", "geo:sfIntersects", "geo:sfTouches", "geo:sfCrosses", "geo:sfWithin",
      "geo:sfContains", "geo:sfOverlaps", "geo:ehEquals", "geo:ehDisjoint", "geo:ehMeet", "geo:ehOverlap",
      "geo:ehCovers", "geo:ehCoveredBy", "geo:ehInside", "geo:ehContains", "geo:rcc8eq", "geo:rcc8dc",
      "geo:rcc8ec", "geo:rcc8po", "geo:rcc8tppi", "geo:rcc8tpp", "geo:rcc8ntpp", "geo:rcc8ntppi"], []},
    {"8.4. Standard Properties for Geo:Geometry", "0", [],
     ["geo:dimension", "geo:coordinateDimension", "geo:spatialDimension", "geo:isEmpty", "geo:isSimple",
      "geo:hasSerialization"], []},
    {"8.5. WKT Serialization", "2/2", ["geo:wktLiteral", "geo:asWKT"], [], []},
    {"8.6. GML Serialization", "0", [], ["geo:gmlLiteral", "geo:asGML"], []},
    {"8.7. Non-Topological Query Functions", "10/10",
     ["geof:distance", "geof:buffer", "geof:convexHull", "geof:intersection", "geof:union", "geof:difference",
      "geof:symDifference", "geof:envelope", "geof:boundary", "geof:getSRID"], [], []},
    {"9.2. Common Query Functions", "1/1", ["geof:relate"], [], []},
    {"9.3. Topological Simple Features Relation Family Query Functions", "8/8",
     ["geof:sfEquals", "geof:sfDisjoint", "geof:sfIntersects", "geof:sfTouches", "geof:sfCrosses",
      "geof:sfWithin", "geof:sfContains", "geof:sfOverlaps"], [], []},
    {"9.4. Topological Egenhofer Relation Family Query Functions", "8/8",
     ["geof:ehEquals", "geof:ehDisjoint", "geof:ehMeet", "geof:ehOverlap", "geof:ehCovers",
      "geof:ehCoveredBy", "geof:ehInside", "geof:ehContains"], [], []},
    {"9.5. Topological RCC8 Relation Family Query Functions", "8/8",
     ["geof:rcc8eq", "geof:rcc8dc", "geof:rcc8ec", "geof:rcc8po", "geof:rcc8tppi", "geof:rcc8tpp",
      "geof:rcc8ntpp", "geof:rcc8ntppi"], [], []}
  ]

  @time_functions [
    "ofn:weeksBetween(date,date)",
    "ofn:weeksBetween(dateTime,dateTime)",
    "ofn:weeksBetween(date,dateTime)",
    "ofn:weeksBetween(dateTime,date)",
    "ofn:daysBetween(date,date)",
    "ofn:daysBetween(dateTime,dateTime)",
    "ofn:daysBetween(date,dateTime)",
    "ofn:daysBetween(dateTime,date)",
    "ofn:hoursBetween(dateTime,dateTime)",
    "ofn:minutesBetween(dateTime,dateTime)",
    "ofn:secondsBetween(dateTime,dateTime)",
    "ofn:millisBetween(dateTime,dateTime)",
    "obdaf:dateTrunc",
    "obdaf:milliseconds-from-dateTime",
    "obdaf:microseconds-from-dateTime",
    "obdaf:week-from-dateTime",
    "obdaf:quarter-from-dateTime",
    "obdaf:decade-from-dateTime",
    "obdaf:century-from-dateTime",
    "obdaf:millenium-from-dateTime"
  ]

  @time_limitations %{
    mixed_date_datetime_ofn: ["Oracle", "Microsoft SQL Server"],
    date_trunc_decade_century_millennium: [
      "AWS Athena", "Denodo (century supported)", "MySQL (century supported)",
      "MariaDB (century supported)", "Oracle", "Presto", "SQLServer", "Snowflake", "Spark", "Trino"
    ],
    date_trunc_second: ["Denodo"],
    date_trunc_millisecond_microsecond: ["AWS Athena", "Denodo", "MySQL", "MariaDB", "Oracle", "Presto", "Trino"],
    postgres_granularity_aliases: %{"millisecond" => "milliseconds", "microsecond" => "microseconds"}
  }

  @r2rml_unsupported [
    "Base IRIs",
    "R2RML default mapping generation",
    "Normalization of binary SQL datatypes"
  ]

  @other_functions ["xsd:date", "obdaf:queryId"]

  @type feature_status :: :supported | :unsupported | :unknown

  @spec version() :: String.t()
  def version, do: @version

  @spec source_identity() :: map()
  def source_identity, do: %{url: @source_url, updated: @source_updated, ontop_version: @version}

  @spec profile() :: map()
  def profile do
    %{
      ontop_version: @version,
      source_updated: @source_updated,
      source_url: @source_url,
      sparql_1_1: sections(@sparql),
      geosparql_1_0: %{sections: sections(@geosparql), units: ["metre", "radian", "degree"]},
      r2rml: %{
        status: :partial,
        description: "Ontop 5.5.0 is documented as almost fully compliant with W3C R2RML.",
        unsupported: @r2rml_unsupported,
        limitations: [
          "Complex SQL queries can require ontop.allowRetrievingBlackBoxViewMetadataFromDB for datatype inference.",
          "Explicit rr:datatype can mitigate missing inference but does not restore missing SQL-value normalization."
        ]
      },
      rdf_1_1: %{
        status: :supported,
        semantics: [
          "RDF 1.0 simple literals are typed as xsd:string",
          "language-tagged literals are typed as rdf:langString"
        ]
      },
      time_functions: %{supported: @time_functions, limitations: @time_limitations},
      other_functions: %{supported: @other_functions}
    }
  end

  @spec standard(atom()) :: {:ok, term()} | {:error, Refusal.t()}
  def standard(name) when is_atom(name) do
    case Map.fetch(profile(), name) do
      {:ok, value} -> {:ok, value}
      :error -> unknown_standard(name)
    end
  end

  @spec feature_status(atom(), String.t()) :: feature_status()
  def feature_status(:sparql_1_1, feature), do: section_feature_status(@sparql, feature)
  def feature_status(:geosparql_1_0, feature), do: section_feature_status(@geosparql, feature)
  def feature_status(:time_functions, feature), do: member_status(@time_functions, feature)
  def feature_status(:other_functions, feature), do: member_status(@other_functions, feature)
  def feature_status(:r2rml, feature), do: if(feature in @r2rml_unsupported, do: :unsupported, else: :unknown)
  def feature_status(:rdf_1_1, "RDF 1.1"), do: :supported
  def feature_status(_standard, _feature), do: :unknown

  @spec require_supported(atom(), String.t()) :: {:ok, map()} | {:error, Refusal.t()}
  def require_supported(standard, feature) do
    case feature_status(standard, feature) do
      :supported ->
        {:ok, %{engine: :ontop, version: @version, standard: standard, feature: feature, status: :supported}}

      status ->
        {:error,
         Refusal.new(
           refusal_code(status),
           {:ontop, standard, feature},
           "Ontop capability is not admitted as fully supported",
           %{status: status, ontop_version: @version, source_updated: @source_updated}
         )}
    end
  end

  @spec counts(atom()) :: %{supported: non_neg_integer(), unsupported: non_neg_integer()}
  def counts(:sparql_1_1), do: section_counts(@sparql)
  def counts(:geosparql_1_0), do: section_counts(@geosparql)

  @doc """
  Read-only live protocol probe corpus for the pinned Ontop image.

  Probes are grouped by published capability section. The crown executes them
  against a real Ontop endpoint; unsupported sections remain catalogued but are
  not executed as if failure were a stronger proof than the upstream contract.
  """
  @spec protocol_probes() :: [map()]
  def protocol_probes do
    [
      probe(:graph_patterns, ["5. Graph Patterns"], """
      PREFIX ex: <https://example.com/ontology/>
      SELECT ?account WHERE { ?account ex:memberOf ?org . FILTER(BOUND(?org)) }
      """),
      probe(:optional, ["6. Including Optional Values"], """
      PREFIX ex: <https://example.com/ontology/>
      SELECT ?account ?id WHERE {
        ?account ex:memberOf ?org .
        OPTIONAL { ?org ex:id ?id }
      }
      """),
      probe(:union, ["7. Matching Alternatives"], """
      PREFIX ex: <https://example.com/ontology/>
      SELECT ?value WHERE {
        { ?value ex:memberOf ?org } UNION { ?value ex:id ?id }
      }
      """),
      probe(:negation, ["8. Negation", "17.4.1. Functional Forms"], """
      PREFIX ex: <https://example.com/ontology/>
      SELECT ?account WHERE {
        ?account ex:memberOf ?org .
        MINUS { ?account ex:missing ?x }
        FILTER NOT EXISTS { ?account ex:missing ?y }
        FILTER(EXISTS { ?account ex:memberOf ?org2 })
      }
      """),
      probe(:property_paths, ["9. Property Paths"], """
      PREFIX ex: <https://example.com/ontology/>
      SELECT ?value WHERE {
        { ?value ex:memberOf ?org }
        UNION { ?org ^ex:memberOf ?value }
        UNION { ?value ex:memberOf/ex:id ?id }
        UNION { ?value (ex:memberOf|ex:id) ?other }
        UNION { ?value !ex:missing ?other2 }
      }
      """),
      probe(:assignment, ["10. Assignment"], """
      PREFIX ex: <https://example.com/ontology/>
      SELECT ?account ?next WHERE {
        VALUES ?n { 1 }
        ?account ex:memberOf ?org .
        BIND(?n + 1 AS ?next)
      }
      """),
      probe(:aggregates, ["11. Aggregates"], """
      PREFIX ex: <https://example.com/ontology/>
      SELECT
        (COUNT(?account) AS ?count) (SUM(?n) AS ?sum) (MIN(?n) AS ?min)
        (MAX(?n) AS ?max) (AVG(?n) AS ?avg)
        (GROUP_CONCAT(STR(?account); separator=",") AS ?concat)
        (SAMPLE(?account) AS ?sample)
      WHERE { ?account ex:memberOf ?org . BIND(1 AS ?n) }
      """),
      probe(:subquery, ["12. Subqueries"], """
      PREFIX ex: <https://example.com/ontology/>
      SELECT ?account WHERE {
        { SELECT ?account WHERE { ?account ex:memberOf ?org } LIMIT 1 }
      }
      """),
      probe(:rdf_dataset, ["13. RDF Dataset"], """
      PREFIX ex: <https://example.com/ontology/>
      SELECT ?s FROM <https://example.com/default> FROM NAMED <https://example.com/named>
      WHERE { OPTIONAL { GRAPH <https://example.com/named> { ?s ?p ?o } } }
      """),
      probe(:solution_modifiers, ["15. Solution Seqs. & Mods."], """
      PREFIX ex: <https://example.com/ontology/>
      SELECT DISTINCT ?account WHERE { ?account ex:memberOf ?org }
      ORDER BY ?account OFFSET 0 LIMIT 2
      """),
      probe(:solution_reduced, ["15. Solution Seqs. & Mods."], """
      PREFIX ex: <https://example.com/ontology/>
      SELECT REDUCED ?account WHERE { ?account ex:memberOf ?org } LIMIT 2
      """),
      probe(:query_select, ["16. Query Forms"], """
      PREFIX ex: <https://example.com/ontology/>
      SELECT ?account WHERE { ?account ex:memberOf ?org } LIMIT 1
      """),
      probe(:query_ask, ["16. Query Forms"], """
      PREFIX ex: <https://example.com/ontology/>
      ASK { ?account ex:memberOf ?org }
      """),
      probe(:query_construct, ["16. Query Forms"], """
      PREFIX ex: <https://example.com/ontology/>
      CONSTRUCT { ?account ex:memberOf ?org } WHERE { ?account ex:memberOf ?org }
      """),
      probe(:query_describe, ["16. Query Forms"], """
      PREFIX ex: <https://example.com/ontology/>
      DESCRIBE ?account WHERE { ?account ex:memberOf ?org } LIMIT 1
      """),
      probe(:rdf_term_functions, ["17.4.2. Functions on RDF Terms"], """
      PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>
      SELECT * WHERE {
        BIND(isIRI(<https://example.com/x>) AS ?a)
        BIND(isBlank(BNODE()) AS ?b)
        BIND(isLiteral("x") AS ?c)
        BIND(isNumeric(1) AS ?d)
        BIND(str(<https://example.com/x>) AS ?e)
        BIND(lang("hello"@en) AS ?f)
        BIND(datatype("x"^^xsd:string) AS ?g)
        BIND(IRI("https://example.com/y") AS ?h)
        BIND(BNODE() AS ?i)
        BIND(UUID() AS ?j)
        BIND(STRUUID() AS ?k)
      }
      """),
      probe(:string_functions, ["17.4.3. Functions on Strings"], """
      SELECT * WHERE {
        BIND(STRLEN("abcdef") AS ?strlen)
        BIND(SUBSTR("abcdef", 2, 3) AS ?substr)
        BIND(UCASE("ab") AS ?ucase)
        BIND(LCASE("AB") AS ?lcase)
        BIND(STRSTARTS("abcdef", "abc") AS ?starts)
        BIND(STRENDS("abcdef", "def") AS ?ends)
        BIND(CONTAINS("abcdef", "cd") AS ?contains)
        BIND(STRBEFORE("abcdef", "cd") AS ?before)
        BIND(STRAFTER("abcdef", "cd") AS ?after)
        BIND(ENCODE_FOR_URI("a b") AS ?encoded)
        BIND(CONCAT("a", "b") AS ?concat)
        BIND(langMatches("en-US", "en") AS ?langmatch)
        BIND(REGEX("abcdef", "^abc") AS ?regex)
        BIND(REPLACE("abcdef", "abc", "xyz") AS ?replace)
      }
      """),
      probe(:numeric_functions, ["17.4.4. Functions on Numerics"], """
      SELECT * WHERE {
        BIND(abs(-2) AS ?abs) BIND(round(1.5) AS ?round)
        BIND(ceil(1.2) AS ?ceil) BIND(floor(1.8) AS ?floor) BIND(RAND() AS ?rand)
      }
      """),
      probe(:date_functions, ["17.4.5. Functions on Dates&Times"], """
      PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>
      SELECT * WHERE {
        BIND(now() AS ?now)
        BIND(year("2026-08-21T12:34:56-07:00"^^xsd:dateTime) AS ?year)
        BIND(month("2026-08-21T12:34:56-07:00"^^xsd:dateTime) AS ?month)
        BIND(day("2026-08-21T12:34:56-07:00"^^xsd:dateTime) AS ?day)
        BIND(hours("2026-08-21T12:34:56-07:00"^^xsd:dateTime) AS ?hours)
        BIND(minutes("2026-08-21T12:34:56-07:00"^^xsd:dateTime) AS ?minutes)
        BIND(seconds("2026-08-21T12:34:56-07:00"^^xsd:dateTime) AS ?seconds)
        BIND(tz("2026-08-21T12:34:56-07:00"^^xsd:dateTime) AS ?tz)
      }
      """),
      probe(:hash_functions, ["17.4.6. Hash Functions"], """
      SELECT * WHERE {
        BIND(MD5("ash_r2rml") AS ?md5) BIND(SHA1("ash_r2rml") AS ?sha1)
        BIND(SHA256("ash_r2rml") AS ?sha256) BIND(SHA384("ash_r2rml") AS ?sha384)
        BIND(SHA512("ash_r2rml") AS ?sha512)
      }
      """),
      probe(:xpath_constructors, ["17.5 XPath Constructor Functions"], """
      PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>
      SELECT * WHERE {
        BIND(xsd:string(1) AS ?string) BIND(xsd:float("1.5") AS ?float)
        BIND(xsd:double("1.5") AS ?double) BIND(xsd:decimal("1.5") AS ?decimal)
        BIND(xsd:integer("1") AS ?integer) BIND(xsd:boolean("true") AS ?boolean)
        BIND(xsd:dateTime("2026-08-21T12:34:56Z") AS ?datetime)
      }
      """),
      probe(:rdf_1_1_literals, [:rdf_1_1], """
      PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>
      PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
      SELECT * WHERE {
        BIND(datatype("simple") = xsd:string AS ?simple_is_string)
        BIND(datatype("hello"@en) = rdf:langString AS ?lang_is_langstring)
      }
      """),
      probe(:time_functions, [:time_functions], """
      PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>
      PREFIX ofn: <http://www.ontotext.com/sparql/functions/>
      PREFIX obdaf: <https://w3id.org/obda/functions#>
      SELECT * WHERE {
        BIND(ofn:weeksBetween("2026-08-01"^^xsd:date, "2026-08-15"^^xsd:date) AS ?weeks)
        BIND(ofn:daysBetween("2026-08-01T00:00:00Z"^^xsd:dateTime, "2026-08-02T00:00:00Z"^^xsd:dateTime) AS ?days)
        BIND(ofn:hoursBetween("2026-08-01T00:00:00Z"^^xsd:dateTime, "2026-08-01T01:00:00Z"^^xsd:dateTime) AS ?hours)
        BIND(ofn:minutesBetween("2026-08-01T00:00:00Z"^^xsd:dateTime, "2026-08-01T00:01:00Z"^^xsd:dateTime) AS ?minutes)
        BIND(ofn:secondsBetween("2026-08-01T00:00:00Z"^^xsd:dateTime, "2026-08-01T00:00:01Z"^^xsd:dateTime) AS ?seconds)
        BIND(ofn:millisBetween("2026-08-01T00:00:00Z"^^xsd:dateTime, "2026-08-01T00:00:01Z"^^xsd:dateTime) AS ?millis)
        BIND(obdaf:dateTrunc("2026-08-21T12:34:56Z"^^xsd:dateTime, "month"^^xsd:string) AS ?truncated)
        BIND(obdaf:week-from-dateTime("2026-08-21T12:34:56Z"^^xsd:dateTime) AS ?week)
        BIND(obdaf:quarter-from-dateTime("2026-08-21T12:34:56Z"^^xsd:dateTime) AS ?quarter)
        BIND(obdaf:decade-from-dateTime("2026-08-21T12:34:56Z"^^xsd:dateTime) AS ?decade)
        BIND(obdaf:century-from-dateTime("2026-08-21T12:34:56Z"^^xsd:dateTime) AS ?century)
        BIND(obdaf:millenium-from-dateTime("2026-08-21T12:34:56Z"^^xsd:dateTime) AS ?millennium)
      }
      """),
      probe(:other_functions, [:other_functions], """
      PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>
      SELECT (xsd:date("2026-08-21") AS ?date) WHERE {}
      """),
      probe(:geosparql_wkt, ["8.5. WKT Serialization"], """
      PREFIX geo: <http://www.opengis.net/ont/geosparql#>
      SELECT ?feature ?wkt WHERE { ?feature geo:asWKT ?wkt } LIMIT 2
      """),
      probe(:geosparql_non_topological, ["8.7. Non-Topological Query Functions"], """
      PREFIX geo: <http://www.opengis.net/ont/geosparql#>
      PREFIX geof: <http://www.opengis.net/def/function/geosparql/>
      PREFIX uom: <http://www.opengis.net/def/uom/OGC/1.0/>
      SELECT * WHERE {
        ?a geo:asWKT ?left . ?b geo:asWKT ?right . FILTER(?a != ?b)
        BIND(geof:distance(?left, ?right, uom:metre) AS ?distance)
        BIND(geof:buffer(?left, 1, uom:metre) AS ?buffer)
        BIND(geof:convexHull(?left) AS ?convex)
        BIND(geof:intersection(?left, ?right) AS ?intersection)
        BIND(geof:union(?left, ?right) AS ?union)
        BIND(geof:difference(?left, ?right) AS ?difference)
        BIND(geof:symDifference(?left, ?right) AS ?sym_difference)
        BIND(geof:envelope(?left) AS ?envelope)
        BIND(geof:boundary(?left) AS ?boundary)
        BIND(geof:getSRID(?left) AS ?srid)
      } LIMIT 1
      """),
      probe(:geosparql_relate, ["9.2. Common Query Functions"], """
      PREFIX geo: <http://www.opengis.net/ont/geosparql#>
      PREFIX geof: <http://www.opengis.net/def/function/geosparql/>
      SELECT (geof:relate(?left, ?right, "T********") AS ?related) WHERE {
        ?a geo:asWKT ?left . ?b geo:asWKT ?right . FILTER(?a != ?b)
      } LIMIT 1
      """),
      probe(:geosparql_sf, ["9.3. Topological Simple Features Relation Family Query Functions"], """
      PREFIX geo: <http://www.opengis.net/ont/geosparql#>
      PREFIX geof: <http://www.opengis.net/def/function/geosparql/>
      SELECT * WHERE {
        ?a geo:asWKT ?left . ?b geo:asWKT ?right . FILTER(?a != ?b)
        BIND(geof:sfEquals(?left, ?right) AS ?equals)
        BIND(geof:sfDisjoint(?left, ?right) AS ?disjoint)
        BIND(geof:sfIntersects(?left, ?right) AS ?intersects)
        BIND(geof:sfTouches(?left, ?right) AS ?touches)
        BIND(geof:sfCrosses(?left, ?right) AS ?crosses)
        BIND(geof:sfWithin(?left, ?right) AS ?within)
        BIND(geof:sfContains(?left, ?right) AS ?contains)
        BIND(geof:sfOverlaps(?left, ?right) AS ?overlaps)
      } LIMIT 1
      """),
      probe(:geosparql_eh, ["9.4. Topological Egenhofer Relation Family Query Functions"], """
      PREFIX geo: <http://www.opengis.net/ont/geosparql#>
      PREFIX geof: <http://www.opengis.net/def/function/geosparql/>
      SELECT * WHERE {
        ?a geo:asWKT ?left . ?b geo:asWKT ?right . FILTER(?a != ?b)
        BIND(geof:ehEquals(?left, ?right) AS ?equals)
        BIND(geof:ehDisjoint(?left, ?right) AS ?disjoint)
        BIND(geof:ehMeet(?left, ?right) AS ?meet)
        BIND(geof:ehOverlap(?left, ?right) AS ?overlap)
        BIND(geof:ehCovers(?left, ?right) AS ?covers)
        BIND(geof:ehCoveredBy(?left, ?right) AS ?covered_by)
        BIND(geof:ehInside(?left, ?right) AS ?inside)
        BIND(geof:ehContains(?left, ?right) AS ?contains)
      } LIMIT 1
      """),
      probe(:geosparql_rcc8, ["9.5. Topological RCC8 Relation Family Query Functions"], """
      PREFIX geo: <http://www.opengis.net/ont/geosparql#>
      PREFIX geof: <http://www.opengis.net/def/function/geosparql/>
      SELECT * WHERE {
        ?a geo:asWKT ?left . ?b geo:asWKT ?right . FILTER(?a != ?b)
        BIND(geof:rcc8eq(?left, ?right) AS ?eq)
        BIND(geof:rcc8dc(?left, ?right) AS ?dc)
        BIND(geof:rcc8ec(?left, ?right) AS ?ec)
        BIND(geof:rcc8po(?left, ?right) AS ?po)
        BIND(geof:rcc8tppi(?left, ?right) AS ?tppi)
        BIND(geof:rcc8tpp(?left, ?right) AS ?tpp)
        BIND(geof:rcc8ntpp(?left, ?right) AS ?ntpp)
        BIND(geof:rcc8ntppi(?left, ?right) AS ?ntppi)
      } LIMIT 1
      """)
    ]
  end

  @spec unprobed_supported_sections(atom()) :: [String.t()]
  def unprobed_supported_sections(:sparql_1_1), do: unprobed(@sparql)
  def unprobed_supported_sections(:geosparql_1_0), do: unprobed(@geosparql)

  defp unprobed(source_sections) do
    supported =
      source_sections
      |> Enum.filter(fn {_name, _coverage, supported, _unsupported, _limitations} -> supported != [] end)
      |> Enum.map(&elem(&1, 0))
      |> MapSet.new()

    probed = protocol_probes() |> Enum.flat_map(& &1.sections) |> MapSet.new()

    supported |> MapSet.difference(probed) |> MapSet.to_list() |> Enum.sort()
  end

  defp sections(entries) do
    Map.new(entries, fn {name, coverage, supported, unsupported, limitations} ->
      {name, %{coverage: coverage, supported: supported, unsupported: unsupported, limitations: limitations}}
    end)
  end

  defp section_feature_status(entries, feature) do
    Enum.find_value(entries, :unknown, fn {_name, _coverage, supported, unsupported, _limitations} ->
      cond do
        feature in supported -> :supported
        feature in unsupported -> :unsupported
        true -> nil
      end
    end)
  end

  defp member_status(values, feature), do: if(feature in values, do: :supported, else: :unknown)

  defp section_counts(entries) do
    Enum.reduce(entries, %{supported: 0, unsupported: 0}, fn
      {_name, _coverage, supported, unsupported, _limitations}, acc ->
        %{supported: acc.supported + length(supported), unsupported: acc.unsupported + length(unsupported)}
    end)
  end

  defp probe(id, sections, query), do: %{id: id, sections: List.wrap(sections), query: String.trim(query)}

  defp refusal_code(:unsupported), do: :REFUSED_OBDA_CAPABILITY_UNSUPPORTED
  defp refusal_code(:unknown), do: :REFUSED_OBDA_CAPABILITY_UNKNOWN

  defp unknown_standard(name) do
    {:error,
     Refusal.new(
       :REFUSED_OBDA_CAPABILITY_UNKNOWN,
       {:ontop, name},
       "unknown Ontop standards profile",
       %{known: [:sparql_1_1, :geosparql_1_0, :r2rml, :rdf_1_1, :time_functions, :other_functions]}
     )}
  end
end
