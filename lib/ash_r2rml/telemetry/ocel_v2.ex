# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Telemetry.OCEL2 do
  @moduledoc """
  Bounded OCEL 2.0 semantic model, validator, and deterministic replay substrate.

  Structural validity and process conformance are separate standings. This
  module validates event/object identities, timestamps, qualified E2O/O2O
  references, and duplicate identities. It does not manufacture a conformance
  score without an independently supplied process model.

  Replay treats equal timestamps as a concurrency layer. Conflicting writes in
  one layer are refused instead of being serialized by enumeration order.
  """

  alias AshR2RML.Refusal

  defmodule Object do
    @moduledoc "An OCEL object instance."
    defstruct [:id, :type, attributes: %{}, time_series: []]
  end

  defmodule Event do
    @moduledoc "An OCEL event with optional qualified E2O relations."
    defstruct [:id, :activity, :timestamp, :lifecycle, omap: [], vmap: %{}, e2o: []]
  end

  defmodule Relationship do
    @moduledoc "A qualified object-to-object relationship."
    defstruct [:source_id, :target_id, :qualifier, :timestamp]
  end

  defmodule Log do
    @moduledoc "A bounded OCEL container."
    defstruct events: [], objects: %{}, o2o: []
  end

  @type validation_result :: {:ok, map()} | {:error, Refusal.t()}

  @doc "Validates NDJSON, event maps, or a bounded OCEL container."
  @spec validate(term()) :: validation_result()
  def validate(raw_events) when is_binary(raw_events) do
    raw_events
    |> String.split("\n", trim: true)
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {line, line_number}, {:ok, acc} ->
      case Jason.decode(line) do
        {:ok, event} when is_map(event) -> {:cont, {:ok, [event | acc]}}
        {:ok, other} -> {:halt, invalid_log("OCEL NDJSON line is not an object", %{line: line_number, value: other})}
        {:error, error} -> {:halt, invalid_log("invalid JSON in OCEL NDJSON", %{line: line_number, error: inspect(error)})}
      end
    end)
    |> case do
      {:ok, events} -> events |> Enum.reverse() |> validate()
      error -> error
    end
  end

  def validate(events) when is_list(events) do
    errors = Enum.flat_map(events, &validate_event_schema/1)
    duplicate_event_ids = duplicate_values(events, &Map.get(&1, "ocel:eid"))

    errors =
      if duplicate_event_ids == [],
        do: errors,
        else: ["duplicate ocel:eid values: #{inspect(duplicate_event_ids)}" | errors]

    if errors == [] do
      objects = events |> Enum.flat_map(&event_object_ids/1) |> Enum.uniq() |> Enum.sort()
      activities = events |> Enum.map(&Map.get(&1, "ocel:activity")) |> Enum.uniq() |> Enum.sort()

      {:ok,
       %{
         valid?: true,
         schema_valid?: true,
         event_count: length(events),
         distinct_object_count: length(objects),
         distinct_activities: activities,
         qualified_e2o_count: Enum.reduce(events, 0, &(length(Map.get(&1, "ocel:e2o", [])) + &2)),
         conformance_evaluated?: false,
         conformance_score: nil
       }}
    else
      invalid_log("OCEL 2.0 structural validation failed", %{errors: Enum.reverse(errors)})
    end
  end

  def validate(%Log{} = log) do
    objects = normalize_object_catalog(log.objects)
    object_errors = validate_object_catalog(objects)
    raw_events = Enum.map(log.events, &event_to_map/1)
    event_result = validate(raw_events)

    reference_errors =
      Enum.flat_map(raw_events, fn event ->
        event_object_ids(event)
        |> Enum.reject(&Map.has_key?(objects, &1))
        |> Enum.map(&"event #{inspect(event["ocel:eid"])} references unknown object #{inspect(&1)}")
      end)

    o2o_errors = Enum.flat_map(log.o2o, &validate_o2o(&1, objects))

    case event_result do
      {:error, refusal} ->
        {:error, refusal}

      {:ok, metrics} when object_errors == [] and reference_errors == [] and o2o_errors == [] ->
        {:ok,
         Map.merge(metrics, %{
           object_count: map_size(objects),
           o2o_count: length(log.o2o),
           object_catalog_valid?: true
         })}

      {:ok, _metrics} ->
        invalid_log("OCEL object/reference validation failed", %{
          errors: object_errors ++ reference_errors ++ o2o_errors
        })
    end
  end

  def validate(other), do: invalid_log("unsupported OCEL input", %{value: inspect(other)})

  defp event_to_map(%Event{} = event) do
    %{
      "ocel:eid" => event.id,
      "ocel:activity" => event.activity,
      "ocel:timestamp" => event.timestamp,
      "ocel:lifecycle" => event.lifecycle,
      "ocel:omap" => event.omap,
      "ocel:vmap" => event.vmap,
      "ocel:e2o" => Enum.map(event.e2o, &normalize_e2o/1)
    }
  end

  defp event_to_map(event) when is_map(event), do: event
  defp event_to_map(other), do: %{"__invalid__" => other}

  defp normalize_object_catalog(objects) when is_map(objects) do
    Map.new(objects, fn
      {key, %Object{} = object} -> {to_string(object.id || key), object}
      {key, object} when is_map(object) -> {to_string(Map.get(object, :id) || Map.get(object, "id") || key), object}
      {key, object} -> {to_string(key), object}
    end)
  end

  defp normalize_object_catalog(objects) when is_list(objects) do
    Enum.reduce(objects, %{}, fn
      %Object{id: id} = object, acc when is_binary(id) -> Map.put(acc, id, object)
      %{"id" => id} = object, acc when is_binary(id) -> Map.put(acc, id, object)
      %{id: id} = object, acc when is_binary(id) -> Map.put(acc, id, object)
      _other, acc -> Map.put(acc, "__invalid_#{map_size(acc)}", :invalid)
    end)
  end

  defp normalize_object_catalog(_), do: %{"__invalid_catalog__" => :invalid}

  defp validate_object_catalog(objects) do
    Enum.flat_map(objects, fn {id, object} ->
      type =
        case object do
          %Object{type: value} -> value
          map when is_map(map) -> Map.get(map, :type) || Map.get(map, "type") || Map.get(map, "ocel:type")
          _ -> nil
        end

      []
      |> maybe_error(not non_empty_binary?(id), "object id must be a non-empty string")
      |> maybe_error(not non_empty_binary?(to_string_or_nil(type)), "object #{inspect(id)} has no type")
    end)
  end

  defp validate_o2o(%Relationship{} = relationship, objects) do
    validate_o2o(
      %{
        source_id: relationship.source_id,
        target_id: relationship.target_id,
        qualifier: relationship.qualifier,
        timestamp: relationship.timestamp
      },
      objects
    )
  end

  defp validate_o2o(relationship, objects) when is_map(relationship) do
    source = get_any(relationship, [:source_id, "source_id", "ocel:source"])
    target = get_any(relationship, [:target_id, "target_id", "ocel:target"])
    qualifier = get_any(relationship, [:qualifier, "qualifier", "ocel:qualifier"])

    []
    |> maybe_error(not non_empty_binary?(source), "O2O source id is missing")
    |> maybe_error(not non_empty_binary?(target), "O2O target id is missing")
    |> maybe_error(not non_empty_binary?(qualifier), "O2O qualifier is missing")
    |> maybe_error(non_empty_binary?(source) and not Map.has_key?(objects, source), "O2O source #{inspect(source)} is unknown")
    |> maybe_error(non_empty_binary?(target) and not Map.has_key?(objects, target), "O2O target #{inspect(target)} is unknown")
  end

  defp validate_o2o(other, _objects), do: ["invalid O2O relationship: #{inspect(other)}"]

  defp validate_event_schema(event) when is_map(event) do
    eid = Map.get(event, "ocel:eid")
    activity = Map.get(event, "ocel:activity")
    timestamp = Map.get(event, "ocel:timestamp")
    omap = Map.get(event, "ocel:omap")
    vmap = Map.get(event, "ocel:vmap", %{})
    e2o = Map.get(event, "ocel:e2o", [])

    []
    |> maybe_error(not non_empty_binary?(eid), "missing or invalid ocel:eid")
    |> maybe_error(not non_empty_binary?(activity), "missing or invalid ocel:activity in #{inspect(eid)}")
    |> maybe_error(not valid_timestamp?(timestamp), "missing or invalid ISO 8601 ocel:timestamp in #{inspect(eid)}")
    |> maybe_error(not is_list(omap), "missing or non-list ocel:omap in #{inspect(eid)}")
    |> maybe_error(is_list(omap) and Enum.any?(omap, &(not non_empty_binary?(&1))), "ocel:omap contains invalid object ids in #{inspect(eid)}")
    |> maybe_error(is_list(omap) and length(omap) != length(Enum.uniq(omap)), "ocel:omap contains duplicate object ids in #{inspect(eid)}")
    |> maybe_error(not is_map(vmap), "ocel:vmap must be a map in #{inspect(eid)}")
    |> Kernel.++(validate_e2o_entries(e2o, eid, omap))
  end

  defp validate_event_schema(other), do: ["event is not a map: #{inspect(other)}"]

  defp validate_e2o_entries(e2o, eid, omap) when is_list(e2o) do
    errors =
      Enum.flat_map(e2o, fn relation ->
        normalized = normalize_e2o(relation)
        oid = normalized["ocel:oid"]
        qualifier = normalized["ocel:qualifier"]

        []
        |> maybe_error(not non_empty_binary?(oid), "E2O object id is missing in #{inspect(eid)}")
        |> maybe_error(not non_empty_binary?(qualifier), "E2O qualifier is missing in #{inspect(eid)}")
      end)

    e2o_ids = e2o |> Enum.map(&normalize_e2o/1) |> Enum.map(& &1["ocel:oid"]) |> Enum.reject(&is_nil/1)

    errors
    |> maybe_error(length(e2o_ids) != length(Enum.uniq(e2o_ids)), "duplicate E2O object relation in #{inspect(eid)}")
    |> maybe_error(
      is_list(omap) and e2o != [] and Enum.sort(Enum.uniq(omap)) != Enum.sort(Enum.uniq(e2o_ids)),
      "ocel:omap and qualified ocel:e2o disagree in #{inspect(eid)}"
    )
  end

  defp validate_e2o_entries(_other, eid, _omap), do: ["ocel:e2o must be a list in #{inspect(eid)}"]

  defp normalize_e2o(%{"ocel:oid" => oid} = relation) do
    %{"ocel:oid" => oid, "ocel:qualifier" => Map.get(relation, "ocel:qualifier") || Map.get(relation, "qualifier")}
  end

  defp normalize_e2o(%{object_id: oid} = relation),
    do: %{"ocel:oid" => oid, "ocel:qualifier" => Map.get(relation, :qualifier)}

  defp normalize_e2o(%{oid: oid} = relation),
    do: %{"ocel:oid" => oid, "ocel:qualifier" => Map.get(relation, :qualifier)}

  defp normalize_e2o({oid, qualifier}), do: %{"ocel:oid" => oid, "ocel:qualifier" => qualifier}
  defp normalize_e2o(other), do: %{"ocel:oid" => nil, "ocel:qualifier" => nil, "invalid" => inspect(other)}

  @doc """
  Reconstructs object histories and explicit object changes from event evidence.

  `ocel:vmap` remains event data. Object-state mutation must be explicit in
  `ocel:objectChanges` as `%{object_id => %{attribute => value}}`.
  """
  @spec reconstruct_from_events(term()) :: {:ok, map()} | {:error, Refusal.t()}
  def reconstruct_from_events(events) when is_list(events) do
    with {:ok, _metrics} <- validate(events),
         {:ok, layers} <- concurrency_layers(events),
         :ok <- ensure_commutative_layers(layers) do
      objects = Enum.reduce(layers, %{}, &apply_layer/2)
      ordered_events = Enum.flat_map(layers, & &1.events)

      {:ok,
       %{
         objects: objects,
         activities_order: Enum.map(ordered_events, & &1["ocel:activity"]),
         concurrency_layers:
           Enum.map(layers, fn layer ->
             %{timestamp: layer.timestamp, event_ids: Enum.map(layer.events, & &1["ocel:eid"])}
           end),
         ordering_semantics: :timestamp_layers,
         total_order_inferred?: false
       }}
    end
  end

  def reconstruct_from_events(other), do: invalid_log("replay requires an event list", %{value: inspect(other)})

  defp concurrency_layers(events) do
    layers =
      events
      |> Enum.group_by(& &1["ocel:timestamp"])
      |> Enum.map(fn {timestamp, group} ->
        %{timestamp: timestamp, unix: timestamp_key(timestamp), events: Enum.sort_by(group, & &1["ocel:eid"])}
      end)
      |> Enum.sort_by(&{&1.unix, &1.timestamp})

    {:ok, layers}
  end

  defp ensure_commutative_layers(layers) do
    Enum.reduce_while(layers, :ok, fn layer, :ok ->
      conflicts = layer_conflicts(layer.events)

      if conflicts == [] do
        {:cont, :ok}
      else
        {:halt,
         {:error,
          Refusal.new(
            :REFUSED_AMBIGUOUS_EVENT_ORDER,
            :ocel_replay,
            "same-timestamp object changes do not commute",
            %{timestamp: layer.timestamp, conflicts: conflicts}
          )}}
      end
    end)
  end

  defp layer_conflicts(events) do
    events
    |> Enum.flat_map(fn event ->
      event_changes(event)
      |> Enum.flat_map(fn {object_id, changes} ->
        Enum.map(changes, fn {attribute, value} -> {{object_id, to_string(attribute)}, value, event["ocel:eid"]} end)
      end)
    end)
    |> Enum.group_by(fn {key, _value, _event_id} -> key end)
    |> Enum.flat_map(fn {key, writes} ->
      values = writes |> Enum.map(fn {_key, value, _eid} -> value end) |> Enum.uniq()
      if length(values) > 1, do: [%{field: key, writes: writes}], else: []
    end)
  end

  defp apply_layer(layer, objects) do
    Enum.reduce(layer.events, objects, fn event, acc ->
      activity = event["ocel:activity"]
      timestamp = event["ocel:timestamp"]
      vmap = event["ocel:vmap"] || %{}
      changes = event_changes(event)

      Enum.reduce(event_object_ids(event), acc, fn object_id, inner ->
        existing = Map.get(inner, object_id, %{id: object_id, attributes: %{}, history: [], last_activity: nil})
        attrs = Map.merge(existing.attributes, Map.get(changes, object_id, %{}))

        Map.put(inner, object_id, %{
          existing
          | attributes: attrs,
            history: existing.history ++ [{activity, timestamp, vmap}],
            last_activity: activity
        })
      end)
    end)
  end

  defp event_changes(event) do
    case Map.get(event, "ocel:objectChanges", %{}) do
      changes when is_map(changes) ->
        Map.new(changes, fn {object_id, attrs} ->
          {to_string(object_id), if(is_map(attrs), do: attrs, else: %{})}
        end)

      _ ->
        %{}
    end
  end

  defp event_object_ids(event) do
    omap = if is_list(Map.get(event, "ocel:omap")), do: Map.get(event, "ocel:omap"), else: []

    e2o =
      if is_list(Map.get(event, "ocel:e2o")) do
        event
        |> Map.get("ocel:e2o")
        |> Enum.map(&normalize_e2o/1)
        |> Enum.map(& &1["ocel:oid"])
        |> Enum.reject(&is_nil/1)
      else
        []
      end

    Enum.uniq(omap ++ e2o)
  end

  defp duplicate_values(items, extractor) do
    items
    |> Enum.map(extractor)
    |> Enum.reject(&is_nil/1)
    |> Enum.frequencies()
    |> Enum.filter(fn {_value, count} -> count > 1 end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.sort()
  end

  defp timestamp_key(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, dt, _offset} -> DateTime.to_unix(dt, :microsecond)
      _ -> 0
    end
  end

  defp valid_timestamp?(timestamp) when is_binary(timestamp),
    do: match?({:ok, _, _}, DateTime.from_iso8601(timestamp))

  defp valid_timestamp?(_), do: false

  defp invalid_log(detail, evidence),
    do: {:error, Refusal.new(:REFUSED_INVALID_OCEL2_LOG, :ocel_validator, detail, evidence)}

  defp maybe_error(errors, true, message), do: [message | errors]
  defp maybe_error(errors, false, _message), do: errors
  defp non_empty_binary?(value), do: is_binary(value) and byte_size(value) > 0
  defp to_string_or_nil(nil), do: nil
  defp to_string_or_nil(value), do: to_string(value)
  defp get_any(map, keys), do: Enum.find_value(keys, &Map.get(map, &1))
end
