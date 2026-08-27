# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.Subject do
  @moduledoc "Exact repository subject admission for GGen-manufactured runtime contracts."

  @sha ~r/\A[0-9a-f]{40}\z/
  @repo ~r/\A[^\/\s]+\/[^\/\s]+\z/

  @spec admit(map()) :: {:ok, map()} | {:error, atom()}
  def admit(%{repo: repo, base: base, head: head} = subject)
      when is_binary(repo) and is_binary(base) and is_binary(head) do
    cond do
      not Regex.match?(@repo, repo) -> {:error, :REFUSED_RUNTIME_REPOSITORY_IDENTITY}
      not Regex.match?(@sha, base) -> {:error, :REFUSED_RUNTIME_BASE_NOT_EXACT}
      not Regex.match?(@sha, head) -> {:error, :REFUSED_RUNTIME_HEAD_NOT_EXACT}
      true -> {:ok, Map.take(subject, [:repo, :base, :head])}
    end
  end

  def admit(_), do: {:error, :REFUSED_RUNTIME_SUBJECT_NOT_EXACT}
end
