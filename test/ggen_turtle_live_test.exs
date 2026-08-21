# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenTurtleLiveTest do
  use ExUnit.Case, async: true

  @turtle_profile """
  @prefix sh: <http://www.w3.org/ns/shacl#> .
  @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
  @prefix schema: <https://schema.org/> .
  @prefix r2ml: <https://seanchatmangpt.github.io/ash_r2rml#> .

  schema:OrganizationShape
      a sh:NodeShape ;
      sh:targetClass schema:Organization ;
      r2ml:ashModule "MyApp.Organization" ;
      r2ml:tableName "organizations" ;
      r2ml:subjectTemplate "https://example.org/organizations/{id}" ;
      r2ml:identity [
          r2ml:identityName "primary" ;
          r2ml:identityKey "id" ;
          r2ml:primaryIdentity true
      ] ;
      sh:property [
          sh:path schema:id ;
          r2ml:ashName "id" ;
          r2ml:postgresType "UUID" ;
          sh:datatype xsd:string ;
          sh:minCount 1 ;
          sh:maxCount 1
      ] ;
      sh:property [
          sh:path schema:name ;
          r2ml:ashName "name" ;
          r2ml:postgresType "TEXT" ;
          sh:datatype xsd:string ;
          sh:minCount 1 ;
          sh:maxCount 1
      ] .

  schema:PersonShape
      a sh:NodeShape ;
      sh:targetClass schema:Person ;
      r2ml:ashModule "MyApp.Person" ;
      r2ml:tableName "people" ;
      r2ml:subjectTemplate "https://example.org/people/{id}" ;
      r2ml:identity [
          r2ml:identityName "primary" ;
          r2ml:identityKey "id" ;
          r2ml:primaryIdentity true
      ] ;
      sh:property [
          sh:path schema:id ;
          r2ml:ashName "id" ;
          r2ml:postgresType "UUID" ;
          sh:datatype xsd:string ;
          sh:minCount 1 ;
          sh:maxCount 1
      ] ;
      sh:property [
          sh:path schema:organizationId ;
          r2ml:ashName "organization_id" ;
          r2ml:postgresType "UUID" ;
          sh:datatype xsd:string ;
          sh:minCount 1 ;
          sh:maxCount 1
      ] ;
      sh:property [
          sh:path schema:name ;
          r2ml:ashName "name" ;
          r2ml:postgresType "TEXT" ;
          sh:datatype xsd:string ;
          sh:minCount 1 ;
          sh:maxCount 1
      ] ;
      sh:property [
          sh:path schema:memberOf ;
          r2ml:ashName "organization" ;
          sh:class schema:Organization ;
          sh:minCount 1 ;
          sh:maxCount 1 ;
          r2ml:storageStrategy "foreign_key" ;
          r2ml:sourceKey "organization_id" ;
          r2ml:destinationKey "id"
      ] .
  """

  test "compiles Turtle SHACL profile into ggen bundle and evaluates generated Ash source code" do
    assert {:ok, bundle} = AshR2RML.Ggen.compile_turtle_bundle(@turtle_profile)

    assert bundle.status == :PARTIAL_ALIVE
    ash_source = bundle.files["generated/ash/ontology_resources.ex"]
    assert is_binary(ash_source)
    assert ash_source =~ "defmodule MyApp.Organization"
    assert ash_source =~ "defmodule MyApp.Person"
    assert ash_source =~ "use Ash.Resource"

    # Evaluate the generated Elixir modules live in runtime memory
    {result, _bindings} = Code.eval_string(ash_source)
    assert result != nil

    # Confirm generated modules are loaded and introspectable by AshR2RML
    assert AshR2RML.Resource.Info.mapped?(MyApp.Organization)
    assert AshR2RML.Resource.Info.mapped?(MyApp.Person)

    {:ok, person_mapping} = AshR2RML.mapping_result(MyApp.Person)
    assert person_mapping.ash_resource == MyApp.Person
    assert person_mapping.class_iris == ["https://schema.org/Person"]
  end
end
