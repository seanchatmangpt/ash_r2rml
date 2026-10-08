defmodule AshR2RML.VKG.SourceIdentityCourtTest do
  use ExUnit.Case, async: true

  alias AshR2RML.VKG.SourceIdentity

  @root "test/fixtures/vkg/source_identity_court"

  for path <- Path.wildcard(Path.join([@root, "*", "*.json"])) |> Enum.sort() do
    @path path

    test "source identity court: #{path}" do
      attrs = @path |> File.read!() |> Jason.decode!()
      expect = Map.fetch!(attrs, "expect")
      input = Map.drop(attrs, ["expect"])

      case expect do
        "ok" ->
          assert {:ok, identity} = SourceIdentity.new(input)
          assert :ok = SourceIdentity.verify(identity, identity.sha256)
          assert byte_size(identity.sha256) == 64

        "REFUSED_VKG_SOURCE_IDENTITY" ->
          assert {:error, %AshR2RML.Refusal{code: :REFUSED_VKG_SOURCE_IDENTITY}} =
                   SourceIdentity.new(input)
      end
    end
  end

  test "court covers every canonical VKG domain and identity boundary" do
    paths = Path.wildcard(Path.join([@root, "*", "*.json"]))

    assert length(paths) == 50
    assert paths |> Enum.map(&Path.basename(Path.dirname(&1))) |> Enum.uniq() |> length() == 10
    assert paths |> Enum.map(&Path.basename(&1, ".json")) |> Enum.uniq() |> length() == 5
  end
end
