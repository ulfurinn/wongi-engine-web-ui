[
  import_deps: [:phoenix],
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
