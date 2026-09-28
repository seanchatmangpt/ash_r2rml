defmodule AshR2RML.VKG.Contract do
  @moduledoc "Fail-closed identity envelope for a virtual knowledge graph federation contract."
  @enforce_keys [:view, :source_identity, :source_sha256, :mapping_sha256, :subject_template]
  defstruct [:view, :source_identity, :source_sha256, :mapping_sha256, :subject_template, authority: :none]
  def admit(%__MODULE__{} = c) do
    with true <- c.authority == :none, true <- digest?(c.source_sha256), true <- digest?(c.mapping_sha256), true <- immutable_source?(c.source_identity), true <- String.contains?(c.subject_template, "{id}") do {:ok, c} else _ -> {:error, :refused_vkg_contract} end
  end
  def admit(_), do: {:error, :refused_vkg_contract}
  defp digest?(v), do: is_binary(v) and Regex.match?(~r/^[0-9a-f]{64}$/, v)
  defp immutable_source?(v), do: is_binary(v) and not String.ends_with?(v, ":mutable")
end
