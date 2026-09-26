# SPDX-License-Identifier: MIT
defmodule AshR2RML.KnowledgeHook.ControlOntology do
  @moduledoc "Executable semantic fence for the Chatman Equilibrium hook-control Turtle."
  @path Path.expand("../../../priv/ontology/chatman_equilibrium_knowledge_hook_control.ttl", __DIR__)
  @required ["kh:KnowledgeHookControl a ce:Policy", "kh:HDDL a ce:Planner",
    "kh:FOND a ce:Planner", "kh:POWL a ce:Planner",
    "ce:authorityCeiling kh:ConstructOnlyAuthority", "ce:requiresExactSubject true",
    "ce:requiresFiniteBound true", "ce:requiresReceipt true", "ce:forbids ce:DO"]
  def path, do: @path
  def validate(path \\ @path) do
    with {:ok, ttl} <- File.read(path), {:ok, _graph} <- RDF.Turtle.read_string(ttl),
         [] <- Enum.reject(@required, &String.contains?(ttl, &1)) do
      {:ok, :admitted}
    else
      {:error, reason} -> {:error, {:ontology_unreadable, reason}}
      missing when is_list(missing) -> {:error, {:ontology_contract_missing, missing}}
    end
  end
end
