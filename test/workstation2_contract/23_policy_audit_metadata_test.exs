# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.PolicyAuditMetadataTest do
  use ExUnit.Case, async: true
  test "field-policy exclusions remain auditable in mapping metadata" do
    assert File.read!("AGENTS.md") =~ "field_policy_excluded_attributes"
  end
end
