# Used by "mix format"
[
  plugins: [Phoenix.LiveView.HTMLFormatter, DoctestFormatter, Styler],
  inputs: [
    "{mix,.formatter,.credo}.exs",
    "{config,lib,test}/**/*.{ex,exs,heex}",
    "apps/*/{lib,config,test}/**/*.{ex,exs}",
    "apps/*/mix.exs"
  ],
  line_length: 98,
  import_deps: [:distillery]
]
