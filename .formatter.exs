[
  import_deps: [:phoenix],
  locals_without_parens: [wongi_engine_webui: 1, wongi_engine_webui: 2],
  export: [locals_without_parens: [wongi_engine_webui: 1, wongi_engine_webui: 2]],
  plugins: [Phoenix.LiveView.HTMLFormatter, Volt.Formatter],
  inputs: [
    "*.{heex,ex,exs}",
    "{config,lib,test}/**/*.{heex,ex,exs}",
    "assets/js/**/*.{js,ts,jsx,tsx}"
  ],
  volt: [
    print_width: 100,
    semi: false,
    single_quote: true,
    trailing_comma: :none,
    arrow_parens: :always
  ]
]
