defmodule AshR2RML.VKG.ReceiptTest do
  use ExUnit.Case, async: true
  alias AshR2RML.VKG.{Contract,Receipt}
  @digest String.duplicate("c",64)
  test "replay identity is deterministic and source-bound" do
    c=%Contract{id:"a",source:"urn:s:a",graph:"urn:g:a",source_sha256:@digest,mapping_sha256:@digest,subject_template:"x/{id}"}
    assert Receipt.build(c,%{rows: 1})==Receipt.build(c,%{rows: 1})
    refute Receipt.build(c,%{rows: 1}).replay_sha256==Receipt.build(c,%{rows: 2}).replay_sha256
  end
end
