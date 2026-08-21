# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Telemetry.OcelAshEmitter do
  @moduledoc """
  Object-centric telemetry for real Ash actions, notifications, and Reactor steps.

  Object identifiers are instance or artifact identities. Resource modules,
  action names, renderer names, and step names are never substituted for missing
  object identity. Qualified `ocel:e2o` relations are emitted alongside the
  compatibility `ocel:omap` projection.
  """

  @action_types [:create, :read, :update, :destroy, :action]
  @default_log_path "priv/ocel/ash-actions.ndjson"

  @spec attach!(keyword()) :: [tuple()]
  def attach!(opts \\ []) do
    log_path = Keyword.get(opts, :log_path, default_log_path())
    File.mkdir_p!(Path.dirname(log_path))
    domains = Keyword.get(opts, :domains, Application.get_env(:ash_r2rml, :ash_domains, []))

    ash_action_handlers =
      for domain <- domains, action_type <- @action_types do
        short_name = Ash.Domain.Info.short_name(domain)
        event = [:ash, short_name, action_type, :stop]
        handler_id = {__MODULE__, domain, action_type, :stop}
        :telemetry.detach(handler_id)
        :telemetry.attach(handler_id, event, &__MODULE__.handle_event/4, %{outcome: :stop, log_path: log_path})
        handler_id
      end

    notification_handler_id = {__MODULE__, :ash, :notification, :stop}
    :telemetry.detach(notification_handler_id)

    :telemetry.attach(
      notification_handler_id,
      [:ash, :notification, :stop],
      &__MODULE__.handle_notification_event/4,
      %{outcome: :stop, log_path: log_path}
    )

    reactor_step_handler_id = {__MODULE__, :ash_r2rml, :reactor, :step, :stop}
    :telemetry.detach(reactor_step_handler_id)

    :telemetry.attach(
      reactor_step_handler_id,
      [:ash_r2rml, :reactor, :step, :stop],
      &__MODULE__.handle_reactor_step_event/4,
      %{outcome: :stop, log_path: log_path}
    )

    reactor_pipe_handler_id = {__MODULE__, :ash_r2rml, :reactor, :pipeline, :stop}
    :telemetry.detach(reactor_pipe_handler_id)

    :telemetry.attach(
      reactor_pipe_handler_id,
      [:ash_r2rml, :reactor, :pipeline, :stop],
      &__MODULE__.handle_reactor_pipeline_event/4,
      %{outcome: :stop, log_path: log_path}
    )

    [reactor_pipe_handler_id, reactor_step_handler_id, notification_handler_id | ash_action_handlers]
  end

  @spec detach_all!([tuple()]) :: :ok
  def detach_all!(handler_ids) do
    Enum.each(handler_ids, &:telemetry.detach/1)
    :ok
  end

  def default_log_path, do: Application.get_env(:ash_r2rml, :ocel_log_path, @default_log_path)

  @doc false
  def handle_event(_event, measurements, metadata, %{outcome: outcome, log_path: log_path}) do
    append_ocel_event!(build_ocel_event(measurements, metadata, outcome), log_path)
    :ok
  end

  @doc false
  def handle_notification_event(_event, measurements, metadata, %{outcome: outcome, log_path: log_path}) do
    append_ocel_event!(build_notification_ocel_event(measurements, metadata, outcome), log_path)
    :ok
  end

  @doc false
  def handle_reactor_step_event(_event, measurements, metadata, %{outcome: outcome, log_path: log_path}) do
    append_ocel_event!(build_reactor_step_ocel_event(measurements, metadata, outcome), log_path)
    :ok
  end

  @doc false
  def handle_reactor_pipeline_event(_event, measurements, metadata, %{outcome: outcome, log_path: log_path}) do
    append_ocel_event!(build_reactor_pipeline_event(measurements, metadata, outcome), log_path)
    :ok
  end

  defp build_ocel_event(measurements, metadata, outcome) do
    resource = metadata[:resource]
    action = metadata[:action]
    result_record = metadata[:result] || metadata[:record]

    {resource_short_name, description, public_attribute_count, r2rml_class} = resource_facts(resource, metadata)
    e2o = action_object_relations(resource_short_name, result_record, metadata)

    event(
      "#{resource_short_name || "unknown_resource"}.#{action || "unknown_action"}",
      e2o,
      %{
        "domain" => inspect(metadata[:domain]),
        "resource" => inspect(resource),
        "resource_description" => description,
        "public_attribute_count" => public_attribute_count,
        "r2rml_class_iri" => r2rml_class,
        "action" => stringify(action),
        "outcome" => stringify(outcome),
        "authorize?" => metadata[:authorize?],
        "actor_present?" => not is_nil(metadata[:actor]),
        "duration_ms" => duration_ms(measurements)
      }
    )
  end

  defp build_notification_ocel_event(measurements, metadata, outcome) do
    notification = metadata[:notification] || %{}
    resource = get_any(notification, [:resource, "resource"]) || metadata[:resource]
    action = get_any(notification, [:action, "action"]) || metadata[:action]
    record = get_any(notification, [:data, "data", :record, "record"]) || metadata[:record] || metadata[:result]
    short_name = resource_short_name(resource)
    e2o = action_object_relations(short_name, record, metadata)

    event(
      "ash.notification.#{action || "unknown"}",
      e2o,
      %{
        "kind" => "ash_notification",
        "resource" => inspect(resource),
        "action" => stringify(action),
        "outcome" => stringify(outcome),
        "duration_ms" => duration_ms(measurements)
      }
    )
  end

  defp build_reactor_step_ocel_event(measurements, metadata, outcome) do
    step_name = metadata[:step]
    result = metadata[:result]
    formatted_step = safe_step_name(step_name)
    {e2o, enriched_vmap} = extract_step_facts(step_name, result)

    event(
      "ash_r2rml.reactor.#{formatted_step}",
      e2o,
      Map.merge(
        %{
          "step" => formatted_step,
          "outcome" => stringify(outcome),
          "duration_ms" => duration_ms(measurements)
        },
        enriched_vmap
      )
    )
  end

  defp build_reactor_pipeline_event(measurements, metadata, outcome) do
    result = metadata[:result]
    e2o = if is_nil(result), do: [], else: [relation(artifact_urn(result), "pipeline_result")]

    event(
      "ash_r2rml.reactor.pipeline_completed",
      e2o,
      %{
        "outcome" => stringify(outcome),
        "duration_ms" => duration_ms(measurements),
        "title" => if(is_map(result), do: Map.get(result, :title), else: nil),
        "status" => if(is_map(result), do: stringify(Map.get(result, :status)), else: nil)
      }
    )
  end

  defp event(activity, e2o, vmap) do
    e2o = e2o |> Enum.reject(&(is_nil(&1["ocel:oid"]))) |> Enum.uniq_by(&{&1["ocel:oid"], &1["ocel:qualifier"]})

    %{
      "ocel:eid" => Ash.UUIDv7.generate(),
      "ocel:activity" => activity,
      "ocel:timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "ocel:omap" => e2o |> Enum.map(& &1["ocel:oid"]) |> Enum.uniq(),
      "ocel:e2o" => e2o,
      "ocel:vmap" => vmap
    }
  end

  defp resource_facts(resource, metadata) do
    if resource && Ash.Resource.Info.resource?(resource) do
      {
        Ash.Resource.Info.short_name(resource),
        Ash.Resource.Info.description(resource),
        resource |> Ash.Resource.Info.public_attributes() |> length(),
        get_r2rml_class(resource)
      }
    else
      {metadata[:resource_short_name], nil, nil, nil}
    end
  end

  defp action_object_relations(short_name, record, metadata) do
    primary =
      case record_id(record) || metadata[:id] do
        nil -> []
        id -> [relation(instance_id(short_name, id), "primary")]
      end

    related =
      record
      |> record_fields()
      |> Enum.flat_map(fn {key, value} ->
        key = to_string(key)

        if not is_nil(value) and String.ends_with?(key, "_id") do
          qualifier = String.replace_suffix(key, "_id", "")
          [relation(instance_id(qualifier, value), qualifier)]
        else
          []
        end
      end)

    actor =
      case metadata[:actor] do
        %{id: id} when not is_nil(id) -> [relation("actor:#{id}", "actor")]
        id when is_binary(id) and id != "" -> [relation("actor:#{id}", "actor")]
        _ -> []
      end

    primary ++ related ++ actor
  end

  defp record_id(%{id: id}) when not is_nil(id), do: id
  defp record_id(%{"id" => id}) when not is_nil(id), do: id
  defp record_id(_), do: nil

  defp record_fields(record) when is_struct(record), do: Map.from_struct(record)
  defp record_fields(record) when is_map(record), do: record
  defp record_fields(_), do: %{}

  defp instance_id(nil, _id), do: nil
  defp instance_id(name, id), do: "#{name}:#{id}"
  defp relation(nil, _qualifier), do: %{"ocel:oid" => nil, "ocel:qualifier" => nil}
  defp relation(id, qualifier), do: %{"ocel:oid" => id, "ocel:qualifier" => qualifier}

  def safe_step_name(step_name) when is_atom(step_name), do: to_string(step_name)

  def safe_step_name({Reactor.Step.Map, map_name, inner_step, index}),
    do: "#{map_name}.#{safe_step_name(inner_step)}.#{index}"

  def safe_step_name({:compose, sub_name}), do: "compose.#{safe_step_name(sub_name)}"
  def safe_step_name({:__reactor__, :transform, key, step}), do: "transform.#{key}.#{safe_step_name(step)}"
  def safe_step_name({:__reactor__, :transform, step}), do: "transform.#{safe_step_name(step)}"
  def safe_step_name(other), do: inspect(other)

  defp extract_step_facts(:compile_bundle, %AshR2RML.Mapping.Bundle{resources: resources}) when is_list(resources) do
    e2o = Enum.map(resources, &relation(AshR2RML.Mapping.mapping_identity(&1), "compiled_resource"))
    class_iris = Enum.flat_map(resources, &List.wrap(Map.get(&1, :class_iris)))
    {e2o, %{"resource_count" => length(resources), "class_iris" => class_iris}}
  end

  defp extract_step_facts(:attach_provenance, %AshR2RML.Mapping.Bundle{resources: resources}) when is_list(resources) do
    e2o = Enum.map(resources, &relation(AshR2RML.Mapping.mapping_identity(&1), "provenance_subject"))
    {e2o, %{"resource_count" => length(resources), "provenance_namespaces" => ["http://www.w3.org/ns/prov#"]}}
  end

  defp extract_step_facts(:render_r2rml_turtle, turtle) when is_binary(turtle) do
    {[relation(content_urn(turtle), "rendered_r2rml")], %{"format" => "text/turtle", "r2rml_turtle_byte_size" => byte_size(turtle)}}
  end

  defp extract_step_facts(:evaluate_differential, %AshR2RML.SPARQL.DifferentialReceipt{verified?: verified, strategies: strategies, query_sha256: query_sha256}) do
    {
      [relation("urn:sha256:#{query_sha256}", "query_evidence")],
      %{"verified?" => verified, "strategies" => Enum.map(strategies, &to_string/1), "query_sha256" => query_sha256}
    }
  end

  defp extract_step_facts(:manifest_banner, banner) when is_binary(banner) do
    {[relation(content_urn(banner), "manifest_banner")], %{"banner_length" => String.length(banner)}}
  end

  defp extract_step_facts(_step, nil), do: {[], %{}}
  defp extract_step_facts(_step, result), do: {[relation(artifact_urn(result), "step_result")], %{}}

  defp artifact_urn(value) do
    value
    |> :erlang.term_to_binary([:deterministic])
    |> sha256()
    |> then(&"urn:ash-r2rml:artifact:#{&1}")
  end

  defp content_urn(binary), do: "urn:sha256:#{sha256(binary)}"
  defp sha256(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)

  defp get_r2rml_class(resource) do
    case AshR2RML.Resource.Info.mapping_result(resource) do
      {:ok, mapping} -> List.first(mapping.class_iris)
      {:error, _} -> nil
    end
  end

  defp resource_short_name(resource) do
    if resource && Ash.Resource.Info.resource?(resource), do: Ash.Resource.Info.short_name(resource), else: nil
  rescue
    _ -> nil
  end

  defp duration_ms(measurements) do
    case measurements[:duration] do
      nil -> nil
      native -> System.convert_time_unit(native, :native, :millisecond)
    end
  end

  defp stringify(nil), do: nil
  defp stringify(value) when is_binary(value), do: value
  defp stringify(value), do: to_string(value)

  defp get_any(map, keys) when is_map(map), do: Enum.find_value(keys, &Map.get(map, &1))
  defp get_any(_, _), do: nil

  defp append_ocel_event!(event, log_path), do: File.write!(log_path, Jason.encode!(event) <> "\n", [:append])
end
