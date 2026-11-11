# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.EncryptedAndPolicyAndTest do
  @moduledoc """
  r2ml:encrypted renders AshCloak against a profile-declared vault (real Cloak vault, real AES-GCM
  round trip on the ETS data layer); unsupported property terms refuse; separate r2ml:policy nodes
  are AND-composed (tenant scope cannot be bypassed by a capability check).
  """
  use ExUnit.Case, async: false

  alias AshR2RML.Ggen

  @prefixes """
  @prefix sh: <http://www.w3.org/ns/shacl#> .
  @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
  @prefix nf: <https://enc.example/ns#> .
  @prefix r2ml: <https://seanchatmangpt.github.io/ash_r2rml#> .
  """

  defp shape(name, props, extra) do
    @prefixes <>
      """
      nf:#{name}Shape a sh:NodeShape ; sh:targetClass nf:#{name} ;
        r2ml:ashModule "Enc.#{name}" ; r2ml:domainModule "Enc.#{name}Dom" ; r2ml:tableName "#{String.downcase(name)}s" ;
        r2ml:subjectTemplate "https://enc.example/#{String.downcase(name)}s/{id}" ;
        r2ml:identity [ r2ml:identityName "primary" ; r2ml:identityKey "id" ; r2ml:primaryIdentity true ] ;
        #{extra}
        sh:property [ sh:path nf:id ; r2ml:ashName "id" ; r2ml:ashType "uuid" ; r2ml:generated true ; r2ml:postgresType "UUID" ; sh:datatype xsd:string ; sh:minCount 1 ; sh:maxCount 1 ] ;
        #{props}
        .
      """
  end

  defp str(path, extra \\ "", min \\ 1),
    do:
      ~s(sh:property [ sh:path nf:#{path} ; r2ml:ashName "#{path}" ; r2ml:postgresType "TEXT" ; sh:datatype xsd:string ; sh:minCount #{min} ; sh:maxCount 1 #{extra} ] ;)

  defp load!(bundle) do
    texts =
      bundle.files
      |> Enum.filter(fn {path, _} -> String.starts_with?(path, "generated/ash/") end)
      |> Enum.sort()
      |> Enum.map(&elem(&1, 1))

    {doms, res} = Enum.split_with(texts, &(&1 =~ "use Ash.Domain"))
    compiled = Code.compile_string(Enum.join(doms ++ res, "\n"))
    modules = Enum.map(compiled, &elem(&1, 0))

    on_exit(fn ->
      for m <- modules, m2 <- [m, Module.concat(Inspect, m)] do
        :code.purge(m2)
        :code.delete(m2)
      end
    end)

    modules
  end

  defp vault! do
    unless Code.ensure_loaded?(Enc.Vault) do
      Code.compile_string("""
      defmodule Enc.Vault do
        use Cloak.Vault, otp_app: :ash_r2rml

        @impl GenServer
        def init(config) do
          key = :crypto.strong_rand_bytes(32)
          {:ok, Keyword.put(config, :ciphers, default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: key, iv_length: 12}) }
        end
      end
      """)
    end

    case apply(Enc.Vault, :start_link, []) do
      {:ok, pid} -> on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
      {:error, {:already_started, _}} -> :ok
    end
  end

  @encrypted "; r2ml:encrypted true"

  describe "r2ml:encrypted" do
    test "renders AshCloak, private plaintext attribute, encrypted_ column in SQL and migration" do
      ttl = shape("Enc1", str("ein", @encrypted, 0) <> str("name"), ~s(r2ml:cloakVault "Enc.Vault" ;))
      assert {:ok, bundle} = Ggen.compile_turtle_bundle(ttl, files: :per_resource)
      ash = bundle.files["generated/ash/enc/enc1.ex"]
      assert ash =~ "AshCloak"
      assert ash =~ "cloak do"
      assert ash =~ "vault Enc.Vault"
      assert ash =~ "attributes [:ein]"
      assert ash =~ ~r/attribute :ein, .*public\?: false/
      assert ash =~ ~r/attribute :name, .*public\?: true/

      sql = Enum.find_value(bundle.files, fn {p, t} -> if p =~ ~r/\.sql$/, do: t end)
      assert sql =~ ~s("encrypted_ein" bytea)
      refute sql =~ ~s("ein" TEXT)

      mig = bundle.files["generated/ecto/semantic_schema_migration.exs"]
      assert mig =~ ~s(add :"encrypted_ein", :binary)
      refute mig =~ ~s(add :"ein",)

      mapping = bundle.files["priv/r2rml/mapping.ttl"]
      refute mapping =~ "ns#ein"
      assert mapping =~ "ns#name"
    end

    test "encrypted profile output is byte-identical across compiles" do
      ttl = shape("Enc5", str("ein", @encrypted, 0), ~s(r2ml:cloakVault "Enc.Vault" ;))
      {:ok, a} = Ggen.compile_turtle_bundle(ttl, files: :per_resource)
      {:ok, b} = Ggen.compile_turtle_bundle(ttl, files: :per_resource)
      assert a.files == b.files
      refute Enum.any?(a.files, fn {_, t} -> t =~ "_:b" end)
    end

    test "encrypted without a vault, or on an identity key, is refused" do
      ttl = shape("Enc2", str("ein", @encrypted, 0), "")
      assert {:error, r} = Ggen.compile_turtle_bundle(ttl)
      assert Enum.any?(List.wrap(r), &(inspect(&1) =~ "cloakVault"))
    end

    test "real vault round trip: ciphertext in storage, plaintext only through the calculation" do
      vault!()
      ttl = shape("Enc3", str("ein", @encrypted, 0) <> str("name"), ~s(r2ml:cloakVault "Enc.Vault" ;))
      assert {:ok, bundle} = Ggen.compile_turtle_bundle(ttl, files: :per_resource)
      # ETS data layer variant: the profile has no repoModule, so actions really run.
      load!(bundle)

      rec =
        Enc.Enc3
        |> Ash.Changeset.for_create(:create, %{name: "n", ein: "12-3456789"})
        |> Ash.create!(authorize?: false)

      assert is_binary(rec.encrypted_ein)
      refute rec.encrypted_ein =~ "12-3456789"

      [stored] = Ash.read!(Enc.Enc3, authorize?: false)
      refute stored.encrypted_ein =~ "12-3456789"
      loaded = Ash.load!(stored, :ein, authorize?: false)
      assert loaded.ein == "12-3456789"
    end
  end

  describe "unsupported r2ml: terms on a property shape" do
    test "refuse instead of silently dropping" do
      ttl = shape("Enc4", str("ein", "; r2ml:encrpyted true", 0), "")
      assert {:error, r} = Ggen.compile_turtle_bundle(ttl)
      assert Enum.any?(List.wrap(r), &(inspect(&1) =~ "encrpyted"))
    end
  end

  describe "r2ml:policy composition" do
    defp check!(name, allowed) do
      unless Code.ensure_loaded?(Module.concat([name])) do
        Code.compile_string("""
        defmodule #{name} do
          use Ash.Policy.SimpleCheck
          def describe(_), do: "#{name}"
          def match?(actor, _context, _opts), do: actor in #{inspect(allowed)}
        end
        """)
      end
    end

    @policies """
    r2ml:policy [ r2ml:policyName "scope" ; r2ml:actionType "read" ; r2ml:authorizeIf "Enc.Checks.TenantScope" ] ;
    r2ml:policy [ r2ml:policyName "cap" ; r2ml:actionType "read" ; r2ml:authorizeIf "Enc.Checks.HasCap" ] ;
    """

    test "separate policy nodes are AND-composed: capability alone cannot bypass tenant scope" do
      check!("Enc.Checks.TenantScope", [:scope_only, :both])
      check!("Enc.Checks.HasCap", [:cap_only, :both])
      ttl = shape("Pol1", str("title"), @policies)
      assert {:ok, bundle} = Ggen.compile_turtle_bundle(ttl, files: :per_resource)
      load!(bundle)

      assert Ash.can?({Enc.Pol1, :read}, :both)
      refute Ash.can?({Enc.Pol1, :read}, :scope_only)
      refute Ash.can?({Enc.Pol1, :read}, :cap_only)
    end

    test "a comma list inside ONE node is OR (documented), so scope must be its own node" do
      check!("Enc.Checks.TenantScope", [:scope_only, :both])
      check!("Enc.Checks.HasCap", [:cap_only, :both])

      one =
        ~s(r2ml:policy [ r2ml:policyName "either" ; r2ml:actionType "read" ; r2ml:authorizeIf "Enc.Checks.TenantScope, Enc.Checks.HasCap" ] ;)

      assert {:ok, bundle} = Ggen.compile_turtle_bundle(shape("Pol2", str("title"), one), files: :per_resource)
      load!(bundle)
      assert Ash.can?({Enc.Pol2, :read}, :cap_only)
    end
  end

  describe "default create/update accept" do
    test "create with params, update a field, update cannot change :id, encrypted round-trips" do
      vault!()
      ttl = shape("Acc1", str("title") <> str("ein", @encrypted, 0), ~s(r2ml:cloakVault "Enc.Vault" ;))
      assert {:ok, a} = Ggen.compile_turtle_bundle(ttl, files: :per_resource)
      assert {:ok, b} = Ggen.compile_turtle_bundle(ttl, files: :per_resource)
      assert a.files == b.files
      load!(a)

      id = Ash.UUID.generate()

      rec =
        Enc.Acc1
        |> Ash.Changeset.for_create(:create, %{id: id, title: "t", ein: "98-7654321"})
        |> Ash.create!(authorize?: false)

      assert rec.id == id

      upd =
        rec
        |> Ash.Changeset.for_update(:update, %{title: "t2"})
        |> Ash.update!(authorize?: false)

      assert upd.title == "t2"

      changeset = Ash.Changeset.for_update(upd, :update, %{id: Ash.UUID.generate()})
      refute changeset.valid?

      loaded = Ash.load!(upd, :ein, authorize?: false)
      assert loaded.ein == "98-7654321"
      assert Ash.Resource.Info.action(Enc.Acc1, :read)
      assert Ash.Resource.Info.action(Enc.Acc1, :destroy)
    end
  end
end
