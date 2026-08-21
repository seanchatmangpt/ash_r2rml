# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Telemetry.OcelAshEmitter do
  @moduledoc """
  Real Object-Centric Event Log (OCEL v2) event emission for every real Ash action,
  Ash notification, and AshR2RML Reactor workflow execution step.

  Conforms to the standard IEEE/W3C OCEL 2.0 JSON specification:
  - `ocel:eid` - Unique event identifier (UUIDv7)
  - `ocel:activity` - Canonical activity name (`resource.action` or `ash_r2rml.reactor.step`)
  - `ocel:timestamp` - ISO 8601 UTC timestamp
  - `ocel:omap` - List of polymorphic object instance identifiers participating in the event
  - `ocel:vmap` - Map of event attributes enriched with genuine Ash and semantic introspection
  """

  require Logger

  @action_types [:create, :read, :update, :destroy, :action]
  @default_log_path "priv/ocel/ash-actions.ndjson"

  @doc """
  Attaches `:telemetry` handlers for every configured Ash domain, for all CRUD action types,
  generic actions, Ash notifications, and AshR2RML Reactor pipeline steps.
  """
  @spec attach!(keyword()) :: [tuple()]
  def attach!(opts \\ []) do
    log_path = Keyword.get(opts, :log_path, default_log_path())
    File.mkdir_p!(Path.dirname(log_path))

    domains = Keyword.get(opts, :domains, Application.get_env(:ash_r2rml, :ash_domains, []))

    ash_action_handlers =
      for domain <- domains,
          action_type <- @action_types do
        short_name = Ash.Domain.Info.short_name(domain)
        event = [:ash, short_name, action_type, :stop]
        handler_id = {__MODULE__, domain, action_type, :stop}

        :telemetry.detach(handler_id)

        :telemetry.attach(
          handler_id,
          event,
          &__MODULE__.handle_event/4,
          %{outcome: :stop, log_path: log_path}
        )

        handler_id
      end

    # Ash Notification Handler
    notification_event = [:ash, :notification, :stop]
    notification_handler_id = {__MODULE__, :ash, :notification, :stop}
    :telemetry.detach(notification_handler_id)

    :telemetry.attach(
      notification_handler_id,
      notification_event,
      &__MODULE__.handle_notification_event/4,
      %{outcome: :stop, log_path: log_path}
    )

    # AshR2RML Reactor Step Handler
    reactor_step_event = [:ash_r2rml, :reactor, :step, :stop]
    reactor_step_handler_id = {__MODULE__, :ash_r2rml, :reactor, :step, :stop}
    :telemetry.detach(reactor_step_handler_id)

    :telemetry.attach(
      reactor_step_handler_id,
      reactor_step_event,
      &__MODULE__.handle_reactor_step_event/4,
      %{outcome: :stop, log_path: log_path}
    )

    # AshR2RML Reactor Pipeline Completion Handler
    reactor_pipe_event = [:ash_r2rml, :reactor, :pipeline, :stop]
    reactor_pipe_handler_id = {__MODULE__, :ash_r2rml, :reactor, :pipeline, :stop}
    :telemetry.detach(reactor_pipe_handler_id)

    :telemetry.attach(
      reactor_pipe_handler_id,
      reactor_pipe_event,
      &__MODULE__.handle_reactor_pipeline_event/4,
      %{outcome: :stop, log_path: log_path}
    )

    [reactor_pipe_handler_id, reactor_step_handler_id, notification_handler_id | ash_action_handlers]
  end

  @doc """
  Detaches all telemetry handlers attached by this module.
  """
  @spec detach_all!([tuple()]) :: :ok
  def detach_all!(handler_ids) do
    Enum.each(handler_ids, &:telemetry.detach/1)
    :ok
  end

  @doc "Default path where OCEL NDJSON records are appended."
  def default_log_path do
    Application.get_env(:ash_r2rml, :ocel_log_path, @default_log_path)
  end

  @doc false
  def handle_event(_event, measurements, metadata, %{outcome: outcome, log_path: log_path}) do
    event = build_ocel_event(measurements, metadata, outcome)
    append_ocel_event!(event, log_path)
    :ok
  end

  @doc false
  def handle_notification_event(_event, measurements, metadata, %{outcome: outcome, log_path: log_path}) do
    event = build_notification_ocel_event(measurements, metadata, outcome)
    append_ocel_event!(event, log_path)
    :ok
  end

  @doc false
  def handle_reactor_step_event(_event, measurements, metadata, %{outcome: outcome, log_path: log_path}) do
    event = build_reactor_step_ocel_event(measurements, metadata, outcome)
    append_ocel_event!(event, log_path)
    :ok
  end

  @doc false
  def handle_reactor_pipeline_event(_event, measurements, metadata, %{outcome: outcome, log_path: log_path}) do
    event = build_reactor_pipeline_event(measurements, metadata, outcome)
    append_ocel_event!(event, log_path)
    :ok
  end

  defp build_ocel_event(measurements, metadata, outcome) do
    resource = metadata[:resource]
    action = metadata[:action]
    result_record = metadata[:result] || metadata[:record]

    {resource_short_name, description, public_attribute_count, r2rml_class} =
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

    duration_ms =
      case measurements[:duration] do
        nil -> nil
        native -> System.convert_time_unit(native, :native, :millisecond)
      end

    primary_object_id =
      cond do
        is_map(result_record) && Map.get(result_record, :id) ->
          "#{resource_short_name}:#{result_record.id}"

        metadata[:id] ->
          "#{resource_short_name}:#{metadata[:id]}"

        true ->
          to_string(resource_short_name)
      end

    related_objects =
      if is_struct(result_record) do
        for {k, v} <- Map.from_struct(result_record),
            is_binary(v) and String.ends_with?(to_string(k), "_id") and not is_nil(v) do
          prefix = to_string(k) |> String.replace_suffix("_id", "")
          "#{prefix}:#{v}"
        end
      else
        []
      end

    actor_object =
      case metadata[:actor] do
        %{id: aid} -> ["actor:#{aid}"]
        aid when is_binary(aid) -> ["actor:#{aid}"]
        _ -> []
      end

    omap = Enum.uniq([primary_object_id | related_objects ++ actor_object])

    %{
      "ocel:eid" => Ash.UUIDv7.generate(),
      "ocel:activity" => "#{resource_short_name}.#{action}",
      "ocel:timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "ocel:omap" => omap,
      "ocel:vmap" => %{
        "domain" => inspect(metadata[:domain]),
        "resource" => inspect(resource),
        "resource_description" => description,
        "public_attribute_count" => public_attribute_count,
        "r2rml_class_iri" => r2rml_class,
        "action" => to_string(action),
        "outcome" => to_string(outcome),
        "authorize?" => metadata[:authorize?],
        "actor_present?" => not is_nil(metadata[:actor]),
        "duration_ms" => duration_ms
      }
    }
  end

  defp build_notification_ocel_event(measurements, metadata, outcome) do
    notification = metadata[:notification] || %{}
    resource = notification[:resource] || metadata[:resource]
    action = notification[:action] || metadata[:action]

    duration_ms =
      case measurements[:duration] do
        nil -> nil
        native -> System.convert_time_unit(native, :native, :millisecond)
      end

    %{
      "ocel:eid" => Ash.UUIDv7.generate(),
      "ocel:activity" => "ash.notification.#{action}",
      "ocel:timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "ocel:omap" => [to_string(resource)],
      "ocel:vmap" => %{
        "kind" => "ash_notification",
        "resource" => inspect(resource),
        "action" => to_string(action),
        "outcome" => to_string(outcome),
        "duration_ms" => duration_ms
      }
    }
  end

  defp build_reactor_step_ocel_event(measurements, metadata, outcome) do
    step_name = metadata[:step]
    result = metadata[:result]

    duration_ms =
      case measurements[:duration] do
        nil -> nil
        native -> System.convert_time_unit(native, :native, :millisecond)
      end

    formatted_step = safe_step_name(step_name)
    {omap, enriched_vmap} = extract_step_facts(step_name, result)

    %{
      "ocel:eid" => Ash.UUIDv7.generate(),
      "ocel:activity" => "ash_r2rml.reactor.#{formatted_step}",
      "ocel:timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "ocel:omap" => omap,
      "ocel:vmap" =>
        Map.merge(
          %{
            "step" => formatted_step,
            "outcome" => to_string(outcome),
            "duration_ms" => duration_ms
          },
          enriched_vmap
        )
    }
  end

  defp build_reactor_pipeline_event(measurements, metadata, outcome) do
    result = metadata[:result]

    duration_ms =
      case measurements[:duration] do
        nil -> nil
        native -> System.convert_time_unit(native, :native, :millisecond)
      end

    %{
      "ocel:eid" => Ash.UUIDv7.generate(),
      "ocel:activity" => "ash_r2rml.reactor.pipeline_completed",
      "ocel:timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "ocel:omap" => ["AshR2RML.GrandExample.PublishingReactor"],
      "ocel:vmap" => %{
        "pipeline" => "AshR2RML.GrandExample.PublishingReactor",
        "outcome" => to_string(outcome),
        "duration_ms" => duration_ms,
        "title" => if(is_map(result), do: Map.get(result, :title), else: nil),
        "status" => if(is_map(result), do: to_string(Map.get(result, :status)), else: nil)
      }
    }
  end

  def safe_step_name(step_name) when is_atom(step_name), do: to_string(step_name)

  def safe_step_name({Reactor.Step.Map, map_name, inner_step, index}),
    do: "#{map_name}.#{safe_step_name(inner_step)}.#{index}"

  def safe_step_name({:compose, sub_name}), do: "compose.#{safe_step_name(sub_name)}"
  def safe_step_name({:__reactor__, :transform, key, step}), do: "transform.#{key}.#{safe_step_name(step)}"
  def safe_step_name({:__reactor__, :transform, step}), do: "transform.#{safe_step_name(step)}"
  def safe_step_name(other), do: inspect(other)

  defp extract_step_facts(:compile_bundle, %AshR2RML.Mapping.Bundle{resources: res}) when is_list(res) do
    omap = Enum.map(res, fn r -> to_string(Map.get(r, :ash_resource) || Map.get(r, :source_module)) end)
    class_iris = Enum.flat_map(res, fn r -> List.wrap(Map.get(r, :class_iris) || Map.get(r, :class_iri)) end)

    {omap, %{"resource_count" => length(res), "class_iris" => class_iris}}
  end

  defp extract_step_facts(:attach_provenance, %AshR2RML.Mapping.Bundle{resources: res}) when is_list(res) do
    omap = Enum.map(res, fn r -> to_string(Map.get(r, :ash_resource) || Map.get(r, :source_module)) end)
    {omap, %{"resource_count" => length(res), "provenance_namespaces" => ["http://www.w3.org/ns/prov#"]}}
  end

  defp extract_step_facts(:render_r2rml_turtle, turtle) when is_binary(turtle) do
    {["W3CR2RMLRenderer"], %{"format" => "text/turtle", "r2rml_turtle_byte_size" => byte_size(turtle)}}
  end

  defp extract_step_facts(:evaluate_differential, %AshR2RML.SPARQL.DifferentialReceipt{
         verified?: v,
         strategies: s,
         query_sha256: q
       }) do
    {["SPARQLDifferential"], %{"verified?" => v, "strategies" => Enum.map(s, &to_string/1), "query_sha256" => q}}
  end

  defp extract_step_facts(:manifest_banner, banner) when is_binary(banner) do
    {["ManifestBanner"], %{"banner_length" => String.length(banner)}}
  end

  defp extract_step_facts(step, _result) do
    {[safe_step_name(step)], %{}}
  end

  defp get_r2rml_class(resource) do
    case Spark.Dsl.Extension.get_opt(resource, [:r2rml], :class_iri, nil) do
      nil -> Spark.Dsl.Extension.get_opt(resource, [:r2rml], :class, nil)
      class_iri -> class_iri
    end
  end

  defp append_ocel_event!(event, log_path) do
    json_line = Jason.encode!(event) <> "\n"
    File.write!(log_path, json_line, [:append])
  end
end
