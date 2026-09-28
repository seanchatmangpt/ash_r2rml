defmodule AshR2RML.VKG.Receipt do
  @moduledoc "Deterministic replay identity for a VKG contract and observation."
  def build(contract, observation) do
    payload={contract.id,contract.source_sha256,contract.mapping_sha256,contract.graph,observation}
    %{subject: contract.id, source_sha256: contract.source_sha256, mapping_sha256: contract.mapping_sha256,
      replay_sha256: payload |> :erlang.term_to_binary([:deterministic]) |> then(&:crypto.hash(:sha256,&1)) |> Base.encode16(case: :lower),
      authority: :NONE, standing: :observed_not_actuated}
  end
end
