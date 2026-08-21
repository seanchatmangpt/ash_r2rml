# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Fortune5.Manufacture do
  @moduledoc """
  Canonical Fortune-5 CONSTRUCT envelope.

  The low-level semantic/ggen manufacturer creates the semantic, DfCM,
  capability and operational contract graph. This envelope dependency-closes
  that graph with deployment, scheduler, Kubernetes-JSON, rollout and deployment
  receipt projections, then recomputes the manufacture receipt over the enlarged
  path/content graph.

  Nothing here writes files. ggen remains the only materialization authority.
  """

  alias AshR2RML.Fortune5.{Deployment, Ggen}

  @receipt_path "receipts/fortune5-manufacture.json"

  @doc "Construct the dependency-closed Fortune-5 ggen graph."
  def compile(resources_or_bundle, opts \\ []) do
    with {:ok, result} <- Ggen.compile(resources_or_bundle, opts),
         {:ok, augmented} <- augment(result, opts) do
      {:ok, augmented}
    end
  end

  @doc "Add deployment projections to an existing low-level Fortune-5 manufacture."
  def augment(%{dfcm: %{frontier: frontier}, files: files, receipt: receipt} = result, opts \\ []) do
    deployment_opts = Keyword.get(opts, :deployment, [])

    with {:ok, deployment_files, deployment_receipts} <-
           build_deployment_files(frontier, deployment_opts) do
      projected_files =
        files
        |> Map.delete(@receipt_path)
        |> Map.merge(deployment_files)

      projected_hashes = file_hashes(projected_files)

      base_receipt =
        receipt
        |> Map.put(:projected_files_sha256, sha256(projected_hashes))
        |> Map.put(:generated_file_count, map_size(projected_files) + 1)
        |> Map.put(:receipt_sha256, nil)
        |> Map.update(:verified, [:deployment_projection_closure], fn verified ->
          Enum.uniq([:deployment_projection_closure | verified])
        end)

      receipt = %{base_receipt | receipt_sha256: sha256(Map.from_struct(base_receipt))}
      files = Map.put(projected_files, @receipt_path, json(receipt))

      {:ok,
       result
       |> Map.put(:receipt, receipt)
       |> Map.put(:files, files)
       |> Map.put(:sha256, file_hashes(files))
       |> Map.put(:deployment, %{
         status: :PARTIAL_ALIVE,
         standing: :deployment_projection_constructed,
         receipts: deployment_receipts,
         files_sha256: sha256(file_hashes(deployment_files))
       })}
    end
  end

  @doc "Verify the fully augmented staged graph."
  def verify_staged(result, observed), do: Ggen.verify_staged(result, observed)

  defp build_deployment_files(frontier, deployment_opts) do
    Enum.reduce_while(frontier, {:ok, %{}, []}, fn candidate, {:ok, files, receipts} ->
      case Deployment.plan(candidate, deployment_opts) do
        {:ok, plan} ->
          candidate_files = deployment_files(plan)
          receipt = deployment_receipt(plan, candidate_files)
          {:cont, {:ok, Map.merge(files, candidate_files), [receipt | receipts]}}

        {:error, plan} ->
          {:halt,
           {:error,
            %{
              code: :REFUSED_DEPLOYMENT_PROJECTION,
              subject: candidate.id,
              evidence: %{refusals: plan.refusals, deployment_plan_sha256: plan.plan_sha256}
            }}}
      end
    end)
    |> case do
      {:ok, files, receipts} -> {:ok, files, Enum.reverse(receipts)}
      other -> other
    end
  end

  defp deployment_files(plan) do
    prefix = "generated/fortune5/candidates/#{plan.candidate_id}/deployment"
    kubernetes = Deployment.kubernetes(plan)
    scheduler = Deployment.scheduler(plan)
    rollout = Deployment.rollout_matrix(plan)

    individual_kubernetes =
      kubernetes
      |> Enum.with_index(1)
      |> Map.new(fn {object, index} ->
        kind = object |> Map.get(:kind, "Object") |> normalize_path_segment()
        name = object |> get_in([:metadata, :name]) |> to_string() |> normalize_path_segment()
        path = "#{prefix}/kubernetes/#{pad(index)}-#{kind}-#{name}.json"
        {path, json(object)}
      end)

    base = %{
      "#{prefix}/plan.json" => json(plan),
      "#{prefix}/scheduler.json" => json(scheduler),
      "#{prefix}/rollout.json" => json(rollout),
      "#{prefix}/kubernetes/all.json" => json(kubernetes),
      "#{prefix}/kubernetes/README.md" => kubernetes_readme(plan, kubernetes)
    }

    Map.merge(base, individual_kubernetes)
  end

  defp deployment_receipt(plan, files) do
    base = %{
      status: :PARTIAL_ALIVE,
      standing: :deployment_projection_constructed_not_applied,
      candidate_sha256: plan.candidate_id,
      deployment_plan_sha256: plan.plan_sha256,
      file_count: map_size(files),
      files_sha256: sha256(file_hashes(files)),
      kubernetes_actuated?: false,
      scheduler_actuated?: false,
      ggen_materialized?: false,
      receipt_sha256: nil
    }

    Map.put(base, :receipt_sha256, sha256(base))
  end

  defp kubernetes_readme(plan, objects) do
    kinds = objects |> Enum.map(&Map.get(&1, :kind)) |> Enum.frequencies() |> Enum.sort()

    """
    # Kubernetes projection for #{plan.candidate_id}

    Status: PARTIAL_ALIVE / construct-only.

    This directory is generated from the same admitted DfCM candidate as the
    semantic, security, resilience, release and verification contracts. It has
    not been applied to a cluster. ggen may materialize these files; a separate
    BRCE/release path is required to actuate them.

    ## Object inventory

    #{Enum.map_join(kinds, "\n", fn {kind, count} -> "- #{kind}: #{count}" end)}

    ## Invariants

    - immutable artifact digest is required before release standing;
    - no Kubernetes Secret objects are generated;
    - secret material is referenced, never embedded;
    - service-account token automount is disabled;
    - containers run non-root with read-only root filesystems and dropped Linux capabilities;
    - default network policy is deny;
    - disruption budgets, topology spread and bounded autoscaling are explicit;
    - BRCE actuator is the only workload role allowed to carry DO capability.
    """
  end

  defp file_hashes(files) do
    files
    |> Enum.map(fn {path, content} ->
      {path, :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)}
    end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Map.new()
  end

  defp normalize_path_segment(value) do
    value
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9._-]+/, "-")
    |> String.trim("-")
  end

  defp pad(index), do: index |> Integer.to_string() |> String.pad_leading(4, "0")

  defp json(term), do: encode_json(term, 0) <> "\n"
  defp encode_json(%_{} = struct, indent), do: encode_json(Map.from_struct(struct), indent)

  defp encode_json(map, indent) when is_map(map) do
    entries =
      map
      |> Enum.map(fn {key, value} -> {json_key(key), value} end)
      |> Enum.sort_by(&elem(&1, 0))

    if entries == [] do
      "{}"
    else
      pad = String.duplicate(" ", indent)
      child = String.duplicate(" ", indent + 2)

      body =
        Enum.map_join(entries, ",\n", fn {key, value} ->
          child <> Jason.encode!(key) <> ": " <> encode_json(value, indent + 2)
        end)

      "{\n" <> body <> "\n" <> pad <> "}"
    end
  end

  defp encode_json(list, indent) when is_list(list) do
    if list == [] do
      "[]"
    else
      pad = String.duplicate(" ", indent)
      child = String.duplicate(" ", indent + 2)
      body = Enum.map_join(list, ",\n", &(child <> encode_json(&1, indent + 2)))
      "[\n" <> body <> "\n" <> pad <> "]"
    end
  end

  defp encode_json(tuple, indent) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> encode_json(indent)

  defp encode_json(nil, _indent), do: "null"
  defp encode_json(true, _indent), do: "true"
  defp encode_json(false, _indent), do: "false"
  defp encode_json(value, _indent) when is_integer(value) or is_float(value), do: to_string(value)
  defp encode_json(value, _indent) when is_atom(value), do: Jason.encode!(Atom.to_string(value))
  defp encode_json(value, _indent) when is_binary(value), do: Jason.encode!(value)
  defp encode_json(value, _indent), do: Jason.encode!(inspect(value))

  defp json_key(key) when is_atom(key), do: Atom.to_string(key)
  defp json_key(key) when is_binary(key), do: key
  defp json_key(key), do: inspect(key)

  defp sha256(term) do
    term
    |> canonical()
    |> :erlang.term_to_binary([:deterministic])
    |> :crypto.hash(:sha256)
    |> Base.encode16(case: :lower)
  end

  defp canonical(%_{} = struct), do: struct |> Map.from_struct() |> canonical()

  defp canonical(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> {canonical(key), canonical(value)} end)
    |> Enum.sort_by(fn {key, _value} -> :erlang.term_to_binary(key, [:deterministic]) end)
  end

  defp canonical(list) when is_list(list), do: Enum.map(list, &canonical/1)
  defp canonical(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> Enum.map(&canonical/1)
  defp canonical(other), do: other
end
