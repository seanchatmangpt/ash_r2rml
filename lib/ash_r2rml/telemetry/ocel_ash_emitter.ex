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
  - `ocel:omap` - List of object identifiers participating in the event
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

    %{
      "ocel:eid" => Ash.UUIDv7.generate(),
      "ocel:activity" => "#{resource_short_name}.#{action}",
      "ocel:timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "ocel:omap" => [to_string(resource_short_name)],
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

  defp extract_step_facts(:verify_inputs, result) do
    case result do
      %{resource_count: count} -> {["InputVerifier"], %{"resource_count" => count, "valid?" => true}}
      _ -> {["InputVerifier"], %{}}
    end
  end

  defp extract_step_facts(:compile_bundle, result) do
    case result do
      %AshR2RML.Mapping.Bundle{resources: res_list} ->
        omap = Enum.map(res_list, &to_string(&1.ash_resource))
        classes = Enum.flat_map(res_list, & &1.class_iris)
        {omap, %{"resource_count" => length(res_list), "class_iris" => classes}}

      _ ->
        {["Compiler"], %{}}
    end
  end

  defp extract_step_facts(:attach_provenance, result) do
    case result do
      %AshR2RML.Mapping.Bundle{resources: res_list} ->
        omap = Enum.map(res_list, &to_string(&1.ash_resource))
        {omap, %{"provenance_namespaces" => ["http://www.w3.org/ns/prov#"], "resource_count" => length(res_list)}}

      _ ->
        {["Provenance"], %{}}
    end
  end

  defp extract_step_facts(:render_r2rml_turtle, turtle) when is_binary(turtle) do
    {["W3CR2RMLRenderer"], %{"r2rml_turtle_byte_size" => byte_size(turtle), "format" => "text/turtle"}}
  end

  defp extract_step_facts(:evaluate_differential, result) do
    case result do
      %AshR2RML.SPARQL.DifferentialReceipt{verified?: v?, strategies: strats, query_sha256: hash} ->
        {["SPARQLDifferential"],
         %{"verified?" => v?, "strategies" => Enum.map(strats, &to_string/1), "query_sha256" => hash}}

      _ ->
        {["SPARQLDifferential"], %{"verified?" => false}}
    end
  end

  defp extract_step_facts(:manifest_banner, banner) when is_binary(banner) do
    {["ManifestBanner"], %{"banner_length" => String.length(banner)}}
  end

  defp extract_step_facts(:publication_package, result) when is_map(result) do
    {["PublicationPackage"], %{"status" => to_string(result[:status]), "title" => result[:title]}}
  end

  defp extract_step_facts(step, _result) do
    {[safe_step_name(step)], %{}}
  end

  defp safe_step_name(step) when is_atom(step), do: to_string(step)
  defp safe_step_name(step) when is_binary(step), do: step
  defp safe_step_name({Reactor.Step.Map, map_name, inner_step, idx}), do: "#{map_name}.#{inner_step}.#{idx}"
  defp safe_step_name({:compose, sub_name}), do: "compose.#{sub_name}"
  defp safe_step_name(step), do: inspect(step)

  defp get_r2rml_class(resource) do
    if function_exported?(Spark.Dsl.Extension, :get_opt, 4) do
      case Spark.Dsl.Extension.get_opt(resource, [:r2rml], :class_iri, nil) do
        nil -> Spark.Dsl.Extension.get_opt(resource, [:r2rml], :class, nil)
        class_iri -> class_iri
      end
    else
      nil
    end
  rescue
    _ -> nil
  end

  defp append_ocel_event!(event, log_path) do
    line = Jason.encode!(event) <> "\n"
    File.write!(log_path, line, [:append])
  rescue
    error ->
      Logger.error("AshR2RML.Telemetry.OcelAshEmitter failed to append OCEL event: #{inspect(error)}")
  end

  @doc "Default path of the OCEL v2 log"
  def default_log_path, do: @default_log_path
end
