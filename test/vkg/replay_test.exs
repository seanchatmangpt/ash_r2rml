defmodule AshR2RML.VKG.ReplayTest do
  use ExUnit.Case, async: true
  alias AshR2RML.VKG.Replay
  test "replay identity changes on observed digest" do
    c=%{source_sha256:String.duplicate("a",64),mapping_sha256:String.duplicate("b",64)}
    a=Replay.identity(c,String.duplicate("c",64),String.duplicate("d",64))
    b=Replay.identity(c,String.duplicate("c",64),String.duplicate("e",64))
    refute Replay.same?(a,b)
  end
end
