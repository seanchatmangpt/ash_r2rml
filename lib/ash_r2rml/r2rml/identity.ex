# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.R2RML.Identity do
  @moduledoc """
  Deterministic names for generated R2RML triples maps.

  `bridge_id/3` derives a name-based UUID (version 5 layout, variant 10) from
  the mapping identity, relationship, predicate and direction, so the same
  mapping always renders the same bridge name.
  """

  alias AshR2RML.Mapping.{ReferenceObjectMap, Resource}

  @doc """
  Returns the `urn:uuid:` name of the bridge triples map for `reference`
  on `resource`; `direction` is `"forward"` or `"inverse"`.
  """
  @spec bridge_id(Resource.t(), ReferenceObjectMap.t(), String.t()) :: String.t()
  def bridge_id(resource, reference, direction) do
    <<a::32, b::16, _::4, c::12, _::2, d::14, e::48, _rest::binary>> =
      {AshR2RML.Mapping.mapping_identity(resource), reference.relationship, reference.predicate_iri, direction}
      |> :erlang.term_to_binary([:deterministic])
      |> then(&:crypto.hash(:sha256, &1))

    <<hex::binary-size(32)>> =
      Base.encode16(<<a::32, b::16, 5::4, c::12, 2::2, d::14, e::48>>, case: :lower)

    <<p1::binary-size(8), p2::binary-size(4), p3::binary-size(4), p4::binary-size(4), p5::binary-size(12)>> = hex
    "urn:uuid:" <> Enum.join([p1, p2, p3, p4, p5], "-")
  end
end
