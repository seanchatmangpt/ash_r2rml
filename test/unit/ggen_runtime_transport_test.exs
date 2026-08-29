# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.TransportTest do
  use ExUnit.Case, async: true

  alias AshR2RML.GgenRuntime.Transport

  test "admits bounded API transport" do
    assert {:ok, %{kind: :api, max_page_size: 100, max_batch_size: 500, streaming: false}} =
             Transport.admit(%{kind: :api, max_page_size: 100, max_batch_size: 500})
  end

  test "refuses unbounded batches" do
    assert {:error, :REFUSED_RUNTIME_BATCH_UNBOUNDED} =
             Transport.admit(%{kind: :api, max_page_size: 100, max_batch_size: 10_001})
  end
end
