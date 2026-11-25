# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.ParityTest do
  use ExUnit.Case, async: true

  test "parity comparison is multiset-based and independent of row/key ordering" do
    left = [
      %{
        "resource" => "urn:uuid:00000000-0000-4000-8000-000000000002",
        "account" => "urn:uuid:00000000-0000-4000-8000-000000000011"
      },
      %{
        "resource" => "urn:uuid:00000000-0000-4000-8000-000000000001",
        "account" => "urn:uuid:00000000-0000-4000-8000-000000000011"
      }
    ]

    right = [
      %{
        account: "urn:uuid:00000000-0000-4000-8000-000000000011",
        resource: "urn:uuid:00000000-0000-4000-8000-000000000001"
      },
      %{
        resource: "urn:uuid:00000000-0000-4000-8000-000000000002",
        account: "urn:uuid:00000000-0000-4000-8000-000000000011"
      }
    ]

    receipt =
      AshR2RML.Parity.compare(:sparql_sql, "cloud:belongsToAccount", left, right, %{
        fixture_sha256: "fixture",
        mapping_sha256: "mapping",
        left_query: "SELECT ?resource ?account WHERE { ?resource <https://schema.org/memberOf> ?account }",
        right_query: "SELECT resource, account FROM resources"
      })

    assert receipt.verified?
    assert receipt.left_result_sha256 == receipt.right_result_sha256
    assert is_binary(receipt.receipt_sha256)
  end
end
