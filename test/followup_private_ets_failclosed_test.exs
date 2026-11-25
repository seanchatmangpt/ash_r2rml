# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.FollowupPrivateEtsFailClosedTest do
  @moduledoc """
  The private-ETS guard in `AshR2RML.OBDA.query/3` fails closed: a resource whose data layer
  cannot be introspected is refused, never treated as "not private".
  """

  use ExUnit.Case, async: false

  alias AshR2RML.Error
  alias AshR2RML.Mapping.{LogicalTable, Resource, SubjectMap}
  alias AshR2RML.OBDA

  defmodule NotAResource do
    @moduledoc false
    def hello, do: :world
  end

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
    end
  end

  test "unintrospectable data layer is refused with REFUSED_PRIVATE_DATA_LAYER" do
    mapping = %Resource{
      ash_resource: NotAResource,
      logical_table: %LogicalTable{table_name: "not_a_resource"},
      subject_map: %SubjectMap{strategy: :template, value: "http://schema.org/{id}", term_type: :iri},
      class_iris: ["https://schema.org/Thing"],
      predicate_object_maps: [],
      identities: [[:id]],
      metadata: %{}
    }

    assert {:error, %Error{code: :REFUSED_PRIVATE_DATA_LAYER, resource: NotAResource} = error} =
             OBDA.query(
               [{NotAResource, mapping}],
               "SELECT ?s WHERE { ?s ?p ?o }",
               domain: Domain
             )

    assert error.details.detail =~ "fail closed"
  end
end
