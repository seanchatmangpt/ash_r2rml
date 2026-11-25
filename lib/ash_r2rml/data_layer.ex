# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.DataLayer do
  @moduledoc """
  Deprecated delegate: data-layer introspection lives in `AshR2RML.Introspection`
  (`backend/1`, `table_name/1`, `schema_name/1`, `join_columns/2`). Delete this module.
  """

  alias AshR2RML.Introspection

  @doc false
  @deprecated "use AshR2RML.Introspection.backend/1"
  defdelegate backend(resource), to: Introspection

  @doc false
  @deprecated "use AshR2RML.Introspection.table_name/1"
  defdelegate table_name(resource), to: Introspection

  @doc false
  @deprecated "use AshR2RML.Introspection.schema_name/1"
  defdelegate schema_name(resource), to: Introspection

  @doc false
  @deprecated "use AshR2RML.Introspection.join_columns/2"
  defdelegate infer_join_columns(resource, relationship), to: Introspection, as: :join_columns
end
