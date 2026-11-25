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
      path: [:r2rml | subject_path(refusals)],
      message: render(refusals)
    )
  end

  # The first refusal naming an attribute or relationship extends the path.
  defp subject_path([%AshR2RML.Refusal{subject: subject} | _]), do: name_path(subject)
  defp subject_path(_other), do: []

  defp name_path({_resource, name}) when is_atom(name) and not is_nil(name), do: [name]

  defp name_path(name) when is_atom(name) and not is_nil(name) do
    if String.starts_with?(Atom.to_string(name), "Elixir."), do: [], else: [name]
  end

  defp name_path(_other), do: []

  defp render(text) when is_binary(text), do: text
  defp render(refusals), do: Enum.map_join(refusals, "; ", &render_one/1)

  defp render_one(%AshR2RML.Refusal{} = refusal) do
    base = "#{refusal.code}: #{refusal.detail}"

    case name_path(refusal.subject) do
      [name] -> base <> " [#{name}]" <> render_evidence(refusal.evidence)
      [] -> base <> render_evidence(refusal.evidence)
    end
  end

  defp render_evidence(evidence) when evidence == %{} or is_nil(evidence), do: ""
  defp render_evidence(evidence), do: " (evidence: #{inspect(evidence)})"
end
