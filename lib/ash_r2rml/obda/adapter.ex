# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OBDA.Adapter do
  @moduledoc """
  Behaviour for OBDA query engines, so a caller can dispatch by config-struct type
  without hand-checking which concrete module to call.

  The only shipped engine is `AshR2RML.OBDA.InMemory` (real `Ash.read!/2` under the
  caller's `actor:`/`tenant:` plus in-process SPARQL algebra, for any Ash data layer).
  The callback contract stays open so other Ash-mediated engines can be added.
  """

  alias AshR2RML.Refusal

  @doc "The engine's canonical identifier, e.g. `:in_memory`."
  @callback engine_name() :: atom()

  @doc """
  Executes `sparql` against whatever `config` names (an Ash resource + mapping IR for
  InMemory), returning an observation struct in `{:ok, _}` on success or
  `{:error, %Refusal{}}` on failure.
  """
  @callback query(config :: struct() | keyword() | map(), sparql :: String.t(), opts :: keyword()) ::
              {:ok, struct()} | {:error, struct() | Refusal.t()}

  @doc """
  Dispatches `query/3` to the adapter module matching `config`'s struct type
  (mirroring `Gno.Store`'s `%adapter_type{} -> adapter_type.<fn>` dispatch).
  """
  @spec dispatch(struct(), String.t(), keyword()) :: {:ok, struct()} | {:error, struct() | Refusal.t()}
  def dispatch(%module{} = config, sparql, opts \\ []) when is_binary(sparql) do
    module.query(config, sparql, opts)
  end
end

defmodule AshR2RML.OBDA.Adapter.InMemoryConfig do
  @moduledoc """
  `AshR2RML.OBDA.Adapter` config for the in-process `AshR2RML.OBDA.InMemory`
  adapter. Wraps one or more `{ash_resource, mapping_resource}` specs so
  `AshR2RML.OBDA.Adapter.dispatch/3` routes through `AshR2RML.OBDA.query/3` (bounded
  `AshR2RML.OBDA.Worker`, returning an `AshR2RML.OBDA.Result`) uniformly for one or many specs.
  """

  @behaviour AshR2RML.OBDA.Adapter

  defstruct [:specs, read_opts: []]

  @type t :: %__MODULE__{
          specs: [AshR2RML.OBDA.InMemory.spec()],
          read_opts: keyword()
        }

  @impl true
  def engine_name, do: :in_memory

  # Routed through `AshR2RML.OBDA.query/3`: bounded worker (timeout/heap), option validation,
  # preflight and an `AshR2RML.OBDA.Result` envelope instead of a raw unbounded materialization.
  @impl true
  def query(%__MODULE__{specs: specs} = config, sparql, opts)
      when is_list(specs) and is_binary(sparql) do
    AshR2RML.OBDA.query(specs, sparql, Keyword.merge(config.read_opts, opts))
  end
end
