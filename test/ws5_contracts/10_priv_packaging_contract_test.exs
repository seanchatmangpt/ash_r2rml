defmodule AshR2RML.WS5.PrivPackagingContractTest do
  use ExUnit.Case, async: true
  @mix Path.expand("../../mix.exs", __DIR__) |> File.read!()
  test "consumer package keeps priv semantic artifacts distributable" do
    assert @mix =~ "CHANGELOG* ash_r2rml.livemd priv"
  end
end
