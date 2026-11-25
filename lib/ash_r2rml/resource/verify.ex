# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Resource.Verify do
  @moduledoc false
  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier

  @impl true
  def verify(dsl) do
    case Verifier.get_persisted(dsl, :ash_r2rml_public_mapping, nil) do
      nil ->
        {:error,
         Spark.Error.DslError.exception(
           message: "AshR2RML mapping was not persisted; semantic compilation did not complete"
         )}

      mapping ->
        validate(mapping)
    end
  end

  defp validate(mapping) do
    case AshR2RML.Mapping.validate(mapping) do
      :ok ->
        :ok

      {:error, refusals} ->
        {:error, Spark.Error.DslError.exception(message: Enum.map_join(refusals, "; ", &"#{&1.code}: #{&1.detail}"))}
    end
  end
end
