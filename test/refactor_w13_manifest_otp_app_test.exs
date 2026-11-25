# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW13ManifestOtpAppTest do
  @moduledoc """
  `Manifest.generate/1` refuses a nil or non-atom `:otp_app` before reaching Ash.
  """
  use ExUnit.Case, async: false

  alias AshR2RML.GrandExample.{Domain, Organization}
  alias AshR2RML.Introspection.Manifest
  alias AshR2RML.Refusal

  setup do
    previous = Application.get_env(:ash_r2rml, :ash_domains)
    Application.put_env(:ash_r2rml, :ash_domains, [Domain])

    on_exit(fn ->
      if previous do
        Application.put_env(:ash_r2rml, :ash_domains, previous)
      else
        Application.delete_env(:ash_r2rml, :ash_domains)
      end
    end)

    :ok
  end

  test "nil otp_app is refused with the otp_app evidence" do
    assert {:error, %Refusal{code: :REFUSED_MANIFEST_GENERATION, evidence: %{otp_app: nil}}} =
             Manifest.generate(otp_app: nil)
  end

  test "string otp_app is refused with the otp_app evidence" do
    assert {:error, %Refusal{code: :REFUSED_MANIFEST_GENERATION, evidence: %{otp_app: "ash_r2rml"}}} =
             Manifest.generate(otp_app: "ash_r2rml")
  end

  test "valid atom otp_app still generates a manifest" do
    assert {:ok, manifest} = Manifest.generate(otp_app: :ash_r2rml)
    assert Enum.any?(manifest.resources, &(&1.module == Organization))
  end
end
