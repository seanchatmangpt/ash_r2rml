# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

[
  import_deps: [:ash],
  plugins: [AshR2RML.Formatter, Spark.Formatter],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  line_length: 120,
  trailing_comma: true,
  local_pipe_with_parens: true,
  single_clause_on_do: true,
  locals_without_parens: [
    class: 1,
    subject: 1,
    property: 2,
    property: 3,
    reference: 2,
    reference: 3,
    graph: 1,
    graph: 2,
    query: 1,
    query: 2
  ],
  export: [
    locals_without_parens: [
      class: 1,
      subject: 1,
      property: 2,
      property: 3,
      reference: 2,
      reference: 3,
      graph: 1,
      graph: 2,
      query: 1,
      query: 2
    ]
  ],
  spark: [
    extensions: [AshR2RML.Resource]
  ]
]
