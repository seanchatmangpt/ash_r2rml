# Legacy path: spatial

AshR2ML does not provide a spatial query engine, spatial index manager, or graph-database geometry storage format.

Spatial/geographic Ash types can participate in RDF mapping only through an explicit, lawful datatype or structured-resource mapping.

See [Datatypes](datatypes.md) and [Custom Ash types](custom-types.md).

Do not infer a GeoSPARQL or other geospatial ontology mapping solely from the presence of an Ash geometry type. The semantic representation must be declared and verified independently.

This file remains as a donor-era compatibility path only.
