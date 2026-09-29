defmodule AshR2RML.VKG do
  @moduledoc """
  Public observe-only Virtual Knowledge Graph facade.

  Preserves source manifest -> admitted catalog -> deterministic plan -> bounded
  execution -> provenance-bearing result -> receipt -> replay verification.

  ## Relation to `AshR2RML.Federation`

  `AshR2RML.Federation` is the in-process determinism substrate: it federates
  and replays inside the BEAM. VKG is a different layer: observe-only,
  exact-source federation of Ontop-backed views, where every contract names its
  exact source identity and digests, authority is always `:NONE`, and results
  are sealed in a receipt that can be replayed. VKG never writes to a source.

  ## Options

    * `:root` - manifest root (default `AshR2RML.VKG.Manifest.default_root/0`)
    * `:previous_receipt` - `%AshR2RML.VKG.Receipt{}`, a receipt id string, or `nil`
    * remaining options (`:capability`, `:engine`, `:merge`, `:max_rows`, ...) go to
      the planner and executor

  All failures are `{:error, %AshR2RML.Refusal{}}`; malformed arguments yield
  `REFUSED_VKG_QUERY_SCOPE` (ids) or `REFUSED_VKG_QUERY_PLAN` (options).
  """

  alias AshR2RML.Refusal
  alias AshR2RML.VKG.{Catalog, Executor, Manifest, Planner, Receipt, Session}

  @doc "Plans, executes and seals a query over the given contract ids."
  @spec query([String.t()], keyword()) :: {:ok, Session.t()} | {:error, Refusal.t()}
  def query(contract_ids, opts \\ [])

  def query(contract_ids, opts) when is_list(contract_ids) and is_list(opts) do
    if Keyword.keyword?(opts) do
      root = Keyword.get(opts, :root, Manifest.default_root())

      with {:ok, catalog} <- Catalog.load(root) do
        run(catalog, contract_ids, opts)
      end
    else
      opts_refusal(opts)
    end
  end

  def query(contract_ids, opts) when is_list(opts) do
    {:error,
     Refusal.new(:REFUSED_VKG_QUERY_SCOPE, :contracts, "VKG contract ids must be a list", %{
       got: inspect(contract_ids)
     })}
  end

  def query(_contract_ids, opts), do: opts_refusal(opts)

  @doc "Queries every admitted contract, loading the catalog exactly once."
  @spec query_all(keyword()) :: {:ok, Session.t()} | {:error, Refusal.t()}
  def query_all(opts \\ [])

  def query_all(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      root = Keyword.get(opts, :root, Manifest.default_root())

      with {:ok, catalog} <- Catalog.load(root) do
        run(catalog, Catalog.ids(catalog), opts)
      end
    else
      opts_refusal(opts)
    end
  end

  def query_all(opts), do: opts_refusal(opts)

  @doc "Loads the admitted catalog from `:root`."
  @spec catalog(keyword()) :: {:ok, Catalog.t()} | {:error, Refusal.t()}
  def catalog(opts \\ [])

  def catalog(opts) when is_list(opts) do
    if Keyword.keyword?(opts),
      do: Catalog.load(Keyword.get(opts, :root, Manifest.default_root())),
      else: opts_refusal(opts)
  end

  def catalog(opts), do: opts_refusal(opts)

  @doc """
  Verifies a session's receipt, plan, result and recorded observations
  (`AshR2RML.VKG.Session.verify/1`, which delegates to `AshR2RML.VKG.Replay`).

  With `catalog: %Catalog{}` (or `root: path`) the session is additionally
  bound to that catalog digest, so a session sealed against a since-changed
  manifest is refused with `REFUSED_VKG_REPLAY`.

  With `key: secret` a receipt signature (`AshR2RML.VKG.Receipt.sign/2`) is
  verified, and `require_signature: true` additionally refuses unsigned
  receipts. The signature is a shared-key MAC, see `AshR2RML.VKG.Receipt`.
  """
  @spec verify(Session.t(), keyword()) :: :ok | {:error, Refusal.t()}
  def verify(session, opts \\ [])

  def verify(%Session{} = session, opts) when is_list(opts) do
    if Keyword.keyword?(opts), do: do_verify(session, opts), else: opts_refusal(opts)
  end

  def verify(%Session{}, opts), do: opts_refusal(opts)

  def verify(other, _opts) do
    {:error,
     Refusal.new(:REFUSED_VKG_REPLAY, :session, "verify requires a VKG session", %{
       got: inspect(other)
     })}
  end

  defp do_verify(session, opts) do
    with :ok <- Session.verify(session, Keyword.take(opts, [:key, :require_signature])),
         {:ok, expected} <- expected_catalog(opts) do
      check_expected(session, expected)
    end
  end

  defp expected_catalog(opts) do
    cond do
      match?(%Catalog{}, opts[:catalog]) -> {:ok, opts[:catalog].sha256}
      Keyword.has_key?(opts, :root) -> with {:ok, c} <- Catalog.load(opts[:root]), do: {:ok, c.sha256}
      true -> {:ok, nil}
    end
  end

  defp check_expected(_session, nil), do: :ok
  defp check_expected(%Session{catalog_sha256: sha}, sha), do: :ok

  defp check_expected(%Session{} = session, expected) do
    {:error,
     Refusal.new(:REFUSED_VKG_REPLAY, :catalog, "session catalog differs from the expected catalog", %{
       session: session.catalog_sha256,
       expected: expected
     })}
  end

  defp run(catalog, contract_ids, opts) do
    query_opts = Keyword.drop(opts, [:root, :previous_receipt, :catalog])

    with {:ok, plan} <- Planner.plan(catalog, contract_ids, query_opts),
         {:ok, result, observations} <- Executor.execute(plan, query_opts) do
      receipt = Receipt.build(plan, result, observations, Keyword.get(opts, :previous_receipt))
      {:ok, Session.new(catalog, plan, result, observations, receipt)}
    end
  end

  defp opts_refusal(opts) do
    {:error,
     Refusal.new(:REFUSED_VKG_QUERY_PLAN, :options, "VKG options must be a keyword list", %{
       got: inspect(opts)
     })}
  end
end
