# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Telemetry.OcelAshEmitter do
  @moduledoc """
  Real Object-Centric Event Log (OCEL v2) event emission for Ash actions,
  notifications, and AshR2RML Reactor workflow execution.

  Reactor events preserve their execution identifier and the stable content
  identity of each step result. This makes one OCEL stream sufficient to trace
  concurrent Reactor work back to the exact semantic artifacts it produced,
  without treating timestamps or scheduler order as semantic identity.
  """

  require Logger

  alias AshR2RML.Evidence

  @action_types [:create, :read, :update, :destroy, :action]
  @default_log_path "priv/ocel/ash-actions.ndjson"

  @doc "Attach telemetry handlers for configured Ash domains and AshR2RML Reactor events."
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

    reactor_pipe_error_handler_id = {__MODULE__, :ash_r2rml, :reactor, :pipeline, :exception}
    :telemetry.detach(reactor_pipe_error_handler_id)

    :telemetry.attach(
      reactor_pipe_error_handler_id,
      [:ash_r2rml, :reactor, :pipeline, :exception],
      &__MODULE__.handle_reactor_pipeline_event/4,
      %{outcome: :error, log_path: log_path}
    )

    [
      reactor_pipe_error_handler_id,
      reactor_pipe_handler_id,
      reactor_step_handler_id,
      notification_handler_id
      | ash_action_handlers
    ]
  end

  @doc "Detach all telemetry handlers attached by this module."
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

    duration_ms = duration_ms(measurements)

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

    e2o =
      [%{"ocel:oid" => primary_object_id, "ocel:qualifier" => "target"}] ++
        Enum.map(related_objects, &%{"ocel:oid" => &1, "ocel:qualifier" => "context"}) ++
        Enum.map(actor_object, &%{"ocel:oid" => &1, "ocel:qualifier" => "actor"})

    %{
      "ocel:eid" => Ash.UUIDv7.generate(),
      "ocel:activity" => "#{resource_short_name}.#{action}",
      "ocel:timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "ocel:lifecycle" => to_string(outcome),
      "ocel:omap" => omap,
      "ocel:e2o" => e2o,
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
    res_str = to_string(resource)

    %{
      "ocel:eid" => Ash.UUIDv7.generate(),
      "ocel:activity" => "ash.notification.#{action}",
      "ocel:timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "ocel:lifecycle" => to_string(outcome),
      "ocel:omap" => [res_str],
      "ocel:e2o" => [%{"ocel:oid" => res_str, "ocel:qualifier" => "resource"}],
      "ocel:vmap" => %{
        "kind" => "ash_notification",
        "resource" => inspect(resource),
        "action" => to_string(action),
        "outcome" => to_string(outcome),
        "duration_ms" => duration_ms(measurements)
      }
    }
  end

  defp build_reactor_step_ocel_event(measurements, metadata, outcome) do
    step_name = metadata[:step]
    result = metadata[:result]
    execution_id = metadata[:execution_id] || Evidence.execution_id(metadata[:context])
    result_evidence_id = metadata[:result_evidence_id] || Evidence.id(result)

    formatted_step = safe_step_name(step_name)
    {object_ids, enriched_vmap} = extract_step_facts(step_name, result)
    {omap, e2o} = with_execution_object(object_ids, execution_id, outcome)

    %{
      "ocel:eid" => Ash.UUIDv7.generate(),
      "ocel:activity" => "ash_r2rml.reactor.#{formatted_step}",
      "ocel:timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "ocel:lifecycle" => to_string(outcome),
      "ocel:omap" => omap,
      "ocel:e2o" => e2o,
      "ocel:vmap" =>
        Map.merge(
          %{
            "step" => formatted_step,
            "outcome" => to_string(outcome),
            "duration_ms" => duration_ms(measurements),
            "execution_id" => execution_id,
            "result_evidence_id" => result_evidence_id
          },
          enriched_vmap
        )
    }
  end

  defp build_reactor_pipeline_event(measurements, metadata, outcome) do
    result = metadata[:result] || metadata[:errors]
    execution_id = metadata[:execution_id] || Evidence.execution_id(metadata[:context])
    result_evidence_id = metadata[:result_evidence_id] || metadata[:error_evidence_id] || Evidence.id(result)
    run_object = execution_object(execution_id) || "AshR2RML.Reactor.Pipeline"

    %{
      "ocel:eid" => Ash.UUIDv7.generate(),
      "ocel:activity" => if(outcome == :error, do: "ash_r2rml.reactor.pipeline_failed", else: "ash_r2rml.reactor.pipeline_completed"),
      "ocel:timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "ocel:lifecycle" => to_string(outcome),
      "ocel:omap" => [run_object],
      "ocel:e2o" => [%{"ocel:oid" => run_object, "ocel:qualifier" => "target"}],
      "ocel:vmap" => %{
        "pipeline" => "AshR2RML.Reactor",
        "execution_id" => execution_id,
        "result_evidence_id" => result_evidence_id,
        "outcome" => to_string(outcome),
        "duration_ms" => duration_ms(measurements),
        "title" => if(is_map(result), do: Map.get(result, :title), else: nil),
        "status" => if(is_map(result) and Map.get(result, :status), do: to_string(Map.get(result, :status)), else: nil)
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

  defp extract_step_facts(step, %AshR2RML.Mapping.Bundle{resources: res} = bundle)
       when step in [:compile_bundle, :compile_resources] and is_list(res) do
    omap = Enum.map(res, fn r -> to_string(Map.get(r, :ash_resource) || Map.get(r, :source_module)) end)
    class_iris = Enum.flat_map(res, fn r -> List.wrap(Map.get(r, :class_iris) || Map.get(r, :class_iri)) end)

    {omap,
     %{
       "resource_count" => length(res),
       "class_iris" => class_iris,
       "mapping_sha256" => Evidence.id(bundle)
     }}
  end

  defp extract_step_facts(:attach_provenance, %AshR2RML.Mapping.Bundle{resources: res} = bundle)
       when is_list(res) do
    omap = Enum.map(res, fn r -> to_string(Map.get(r, :ash_resource) || Map.get(r, :source_module)) end)

    {omap,
     %{
       "resource_count" => length(res),
       "provenance_namespaces" => ["http://www.w3.org/ns/prov#"],
       "mapping_sha256" => Evidence.id(bundle)
     }}
  end

  defp extract_step_facts(:render_r2rml_turtle, turtle) when is_binary(turtle) do
    {["W3CR2RMLRenderer"],
     %{
       "format" => "text/turtle",
       "r2rml_turtle_byte_size" => byte_size(turtle),
       "r2rml_sha256" => Evidence.sha256(turtle)
     }}
  end

  defp extract_step_facts(:evaluate_differential, %AshR2RML.SPARQL.DifferentialReceipt{} = receipt) do
    {["SPARQLDifferential"],
     %{
       "verified?" => receipt.verified?,
       "strategies" => Enum.map(receipt.strategies, &to_string/1),
       "query_sha256" => receipt.query_sha256,
       "differential_receipt_sha256" => receipt.receipt_sha256
     }}
  end

  defp extract_step_facts(:manifest_banner, banner) when is_binary(banner) do
    {["ManifestBanner"], %{"banner_length" => String.length(banner), "banner_sha256" => Evidence.sha256(banner)}}
  end

  defp extract_step_facts(step, _result) do
    {[safe_step_name(step)], %{}}
  end

  defp with_execution_object(object_ids, execution_id, outcome) do
    target_qualifier = if(outcome == :error, do: "compensates", else: "target")

    target_relations =
      Enum.map(object_ids, fn oid ->
        %{"ocel:oid" => oid, "ocel:qualifier" => target_qualifier}
      end)

    case execution_object(execution_id) do
      nil ->
        {Enum.uniq(object_ids), target_relations}

      run_object ->
        {
          Enum.uniq([run_object | object_ids]),
          [%{"ocel:oid" => run_object, "ocel:qualifier" => "context"} | target_relations]
        }
    end
  end

  defp execution_object(execution_id) when is_binary(execution_id) and execution_id != "",
    do: "reactor-run:#{execution_id}"

  defp execution_object(_), do: nil

  defp get_r2rml_class(resource) do
    case Spark.Dsl.Extension.get_opt(resource, [:r2rml], :class_iri, nil) do
      nil -> Spark.Dsl.Extension.get_opt(resource, [:r2rml], :class, nil)
      class_iri -> class_iri
    end
  end

  defp duration_ms(measurements) do
    case measurements[:duration] do
      nil -> nil
      native -> System.convert_time_unit(native, :native, :millisecond)
    end
  end

  defp append_ocel_event!(event, log_path) do
    json_line = Jason.encode!(event) <> "\n"
    File.write!(log_path, json_line, [:append])
  end
end
