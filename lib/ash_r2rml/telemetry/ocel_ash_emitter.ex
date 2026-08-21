# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Telemetry.OcelAshEmitter do
  @moduledoc """
  Real Object-Centric Event Log (OCEL v2) event emission for every real Ash action,
  enriched via real Ash introspection (`Ash.Resource.Info`), `AshR2RML` semantic mapping
  metadata, and correlated with OpenTelemetry-compatible `:telemetry` events.

  Conforms to the standard IEEE/W3C OCEL 2.0 JSON specification:
  - `ocel:eid` - Unique event identifier (UUID)
  - `ocel:activity` - Canonical activity name (`resource.action`)
  - `ocel:timestamp` - ISO 8601 UTC timestamp
  - `ocel:omap` - List of object identifiers associated with the event
  - `ocel:vmap` - Map of event attributes enriched with Ash introspection
  """

  require Logger

  @action_types [:create, :read, :update, :destroy, :action]
  @default_log_path "priv/ocel/ash-actions.ndjson"

  @doc """
  Attaches `:telemetry` handlers for every configured Ash domain, for all CRUD action types,
  generic actions, and Ash notification events.
  """
  @spec attach!(keyword()) :: [tuple()]
  def attach!(opts \\ []) do
    log_path = Keyword.get(opts, :log_path, default_log_path())
    File.mkdir_p!(Path.dirname(log_path))

    domains = Keyword.get(opts, :domains, Application.get_env(:ash_r2rml, :ash_domains, []))

    handler_ids =
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

    # Also attach to Ash notification events
    notification_event = [:ash, :notification, :stop]
    notification_handler_id = {__MODULE__, :ash, :notification, :stop}
    :telemetry.detach(notification_handler_id)

    :telemetry.attach(
      notification_handler_id,
      notification_event,
      &__MODULE__.handle_notification_event/4,
      %{outcome: :stop, log_path: log_path}
    )

    [notification_handler_id | handler_ids]
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
