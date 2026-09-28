defmodule AshR2RML.VKG.Contract do
  @moduledoc "Exact-subject federation contract for a virtual knowledge graph source."
  @enforce_keys [:id, :source, :graph, :source_sha256, :mapping_sha256, :subject_template]
  defstruct [:id, :source, :graph, :source_sha256, :mapping_sha256, :subject_template, authority: :NONE, standing: :constructed_not_actuated]
  @type t :: %__MODULE__{}
  def admit(%__MODULE__{}=c) do
    with true <- digest?(c.source_sha256),
         true <- digest?(c.mapping_sha256),
         :NONE <- c.authority,
         true <- is_binary(c.source) and is_binary(c.graph) and is_binary(c.subject_template) do
      {:ok, c}
    else
      _ -> {:error, :REFUSED_VKG_CONTRACT_IDENTITY}
    end
  end
  def admit(_), do: {:error, :REFUSED_VKG_CONTRACT_SHAPE}
  defp digest?(v), do: is_binary(v) and byte_size(v)==64 and String.match?(v, ~r/\A[0-9a-f]{64}\z/)
end
