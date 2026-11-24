# SPDX-FileCopyrightText: 2026 ash_r2rml contributors
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Error do
  @moduledoc """
  Structured exception carrying a typed refusal code plus machine-readable context.

  Build with `new/2` or convert an `%AshR2RML.Refusal{}` with `from_refusal/1`.

      iex> e = AshR2RML.Error.new(:REFUSED_QUERY_TIMEOUT, hint: "raise the timeout")
      iex> e.code
      :REFUSED_QUERY_TIMEOUT
      iex> Exception.message(e) =~ "REFUSED_QUERY_TIMEOUT"
      true
  """

  alias AshR2RML.Refusal

  defexception [:code, :message, :resource, :field, :sparql_clause, :hint, details: %{}]

  @type t :: %__MODULE__{
          code: atom(),
          message: String.t() | nil,
          resource: module() | nil,
          field: atom() | String.t() | nil,
          sparql_clause: String.t() | nil,
          hint: String.t() | nil,
          details: map()
        }

  @catalog %{
    REFUSED_INVALID_CLASS_IRI:
      {"class IRI is not a valid absolute IRI", "set rdf class to an absolute IRI such as https://example.com/Thing"},
    REFUSED_MISSING_SUBJECT_MAP:
      {"resource has no subject map", "declare a subject template or class in the r2rml block"},
    REFUSED_NON_UNIQUE_SEMANTIC_IDENTITY:
      {"semantic identity is not unique", "back the subject with a primary key or an identity declared eager_check"},
    REFUSED_UNMAPPED_DATATYPE:
      {"attribute type has no XSD datatype mapping",
       "set an explicit datatype in the rdf block or use a type implementing AshR2RML.Type"},
    REFUSED_AMBIGUOUS_RELATIONSHIP:
      {"relationship maps ambiguously", "declare exactly one predicate and join condition for the relationship"},
    REFUSED_INVALID_JOIN_CONDITION:
      {"join condition is invalid", "join on existing attributes of the source and destination resources"},
    REFUSED_RELATIONSHIP_WITHOUT_PREDICATE:
      {"relationship has no predicate", "add an rdf do predicate ... end block to the relationship"},
    REFUSED_R2RML_JOIN_WITHOUT_IDENTITY:
      {"R2RML join target has no identity", "give the target resource a subject map with a unique identity"},
    REFUSED_UNPROVEN_EQUIVALENCE:
      {"equivalence between terms is unproven",
       "declare the equivalence explicitly or remove the owl:sameAs style claim"},
    REFUSED_UNSUPPORTED_SPARQL_FEATURE:
      {"SPARQL feature is not supported by the in-memory OBDA backend",
       "rewrite the query using supported clauses (BGP, FILTER, LIMIT)"},
    REFUSED_RESULT_LIMIT_EXCEEDED: {"result row limit exceeded", "add a LIMIT or raise the max_results bound"},
    REFUSED_TRIPLE_LIMIT_EXCEEDED: {"triple limit exceeded", "narrow the query or raise the max_triples bound"},
    REFUSED_MEMORY_LIMIT_EXCEEDED: {"memory limit exceeded", "narrow the query or raise the max_memory bound"},
    REFUSED_QUERY_TIMEOUT: {"query exceeded its time budget", "narrow the query or raise the timeout bound"},
    REFUSED_MISSING_TENANT: {"tenant is required but missing", "pass a tenant in the query options"},
    REFUSED_MISSING_SUBJECT_KEY: {"subject key is missing", "supply every attribute the subject template references"},
    REFUSED_UNAUTHORIZED: {"actor is not authorized", "pass an actor permitted by the resource policies"},
    REFUSED_INVALID_SUBJECT_IRI:
      {"subject IRI does not match the resource template", "use an IRI produced by AshR2RML.Subject.to_iri/2"},
    REFUSED_NON_INVERTIBLE_TEMPLATE:
      {"subject template cannot be inverted", "use a template with delimited, distinct placeholders"},
    UNSUPPORTED_TERM_TYPE: {"term type is unsupported", "use iri, literal or blank_node term types"},
    UNSUPPORTED_ASH_TYPE: {"Ash type is unsupported", "implement AshR2RML.Type for the custom type"}
  }

  @doc "Builds an error. Options: `:resource`, `:field`, `:sparql_clause`, `:hint`, `:details`, `:message`."
  @spec new(atom(), keyword()) :: t()
  def new(code, opts \\ []) when is_atom(code) do
    err = %__MODULE__{
      code: code,
      resource: opts[:resource],
      field: opts[:field],
      sparql_clause: opts[:sparql_clause],
      hint: opts[:hint] || default_hint(code),
      details: Map.new(opts[:details] || %{}),
      message: opts[:message]
    }

    %{err | message: build_message(err)}
  end

  @doc "Converts a `%AshR2RML.Refusal{}`; resource/field/clause come from subject and evidence."
  @spec from_refusal(Refusal.t()) :: t()
  def from_refusal(%Refusal{code: code, subject: subject, detail: detail, evidence: evidence}) do
    evidence = if is_map(evidence), do: evidence, else: %{}
    {s_resource, s_field} = split_subject(subject)

    new(code,
      resource: Map.get(evidence, :resource, s_resource),
      field: Map.get(evidence, :field, s_field),
      sparql_clause: Map.get(evidence, :sparql_clause, Map.get(evidence, :clause)),
      hint: Map.get(evidence, :hint),
      details: Map.merge(evidence, %{detail: detail, subject: subject})
    )
  end

  @impl true
  def message(%__MODULE__{message: m}) when is_binary(m), do: m
  def message(%__MODULE__{} = e), do: build_message(e)

  defp split_subject({resource, field}) when is_atom(resource) and not is_nil(resource),
    do: {resource, field}

  defp split_subject(resource) when is_atom(resource) and not is_nil(resource),
    do: {resource, nil}

  defp split_subject(_), do: {nil, nil}

  defp default_hint(code) do
    case @catalog do
      %{^code => {_, hint}} -> hint
      _ -> nil
    end
  end

  defp build_message(%__MODULE__{code: code} = e) do
    summary =
      case @catalog do
        %{^code => {s, _}} -> s
        _ -> "refused"
      end

    ctx =
      [
        e.resource && "resource: #{inspect(e.resource)}",
        e.field && "field: #{inspect(e.field)}",
        e.sparql_clause && "clause: #{e.sparql_clause}"
      ]
      |> Enum.filter(& &1)

    detail =
      case e.details do
        %{detail: d} when is_binary(d) and d != "" -> " - #{d}"
        _ -> ""
      end

    ctx_s = if ctx == [], do: "", else: " (#{Enum.join(ctx, ", ")})"
    hint_s = if e.hint, do: " Hint: #{e.hint}", else: ""
    "#{code}: #{summary}#{ctx_s}#{detail}.#{hint_s}"
  end
end
