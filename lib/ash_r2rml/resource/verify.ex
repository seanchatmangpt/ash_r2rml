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
        {:error, diagnostic(Map.get(mapping, :ash_resource), refusals)}
    end
  end

  @doc false
  # Builds the DslError with module and path; the message keeps each REFUSED_*
  # code, detail and evidence.
  @spec diagnostic(module() | nil, [AshR2RML.Refusal.t()] | String.t()) :: Spark.Error.DslError.t()
  def diagnostic(module, refusals) do
    Spark.Error.DslError.exception(
      module: module,
      path: [:r2rml],
      message: render(refusals)
    )
  end

  defp render(text) when is_binary(text), do: text
  defp render(refusals), do: Enum.map_join(refusals, "; ", &render_one/1)

  defp render_one(%AshR2RML.Refusal{code: code, detail: detail, evidence: evidence})
       when evidence == %{} or is_nil(evidence),
       do: "#{code}: #{detail}"

  defp render_one(%AshR2RML.Refusal{code: code, detail: detail, evidence: evidence}),
    do: "#{code}: #{detail} (evidence: #{inspect(evidence)})"
end
