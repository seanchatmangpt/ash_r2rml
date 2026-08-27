# Manufacture a GGen runtime integration contract

`AshR2RML.GgenRuntime.contract/1` is a SELECT/CONSTRUCT adapter for the `ash-runtime-integration-contract-pack` in ggen-marketplace. It does not execute runtime actions or write generated files.

```elixir
{:ok, contract} =
  AshR2RML.GgenRuntime.contract(%{
    subject: %{
      repo: "seanchatmangpt/ash_r2rml",
      base: "main",
      head: "067954ad406fd637"
    },
    authority: %{policy: "project2", action: "construct"},
    runtime: %{
      resource: "Example.Resource",
      action: "read"
    }
  })
```

The result contains a deterministic runtime digest, replay identity, exact subject, authority policy, canonical OCEL evidence path, and marketplace pack identity. Pass those admitted facts to GGen; GGen owns rendering and filesystem actuation. Runtime DO authority remains outside this adapter.

A short/non-exact head returns `REFUSED_RUNTIME_SUBJECT_NOT_EXACT`. Missing authority returns `REFUSED_RUNTIME_AUTHORITY_MISSING`. Incomplete input returns `REFUSED_RUNTIME_CONTRACT_INCOMPLETE`.
