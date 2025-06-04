defmodule Archethic.MixProject do
  use Mix.Project

  def project do
    [
      app: :archethic,
      version: "1.7.0",
      build_path: "_build",
      config_path: "config/config.exs",
      deps_path: "deps",
      lockfile: "mix.lock",
      aliases: aliases(),
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      start_concurrently: true,
      deps: deps(),
      compilers: [:elixir_make] ++ Mix.compilers(),
      elixirc_paths: elixirc_paths(Mix.env()),
      elixirc_options: [warnings_as_errors: true],
      dialyzer: dialyzer()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [
        :public_key,
        :crypto,
        :logger,
        :inets,
        :os_mon,
        :runtime_tools,
        :xmerl,
        :crypto
      ],
      mod: {Archethic.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specify dialyzer path
  defp dialyzer do
    [
      plt_add_apps: [:mix, :ex_unit],
      plt_core_path: "priv/plts",
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Web Server
      {:phoenix, "~> 1.7"},
      {:phoenix_html, "~> 4.2"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_pubsub, "~> 2.1"},
      {:phoenix_view, "~> 2.0"},
      {:phoenix_html_helpers, "~> 1.0"},
      {:plug_cowboy, "~> 2.7"},
      {:cors_plug, "~> 3.0"},
      {:plug_attack, "~> 0.4.3"},
      {:ecto, "~> 3.12"},

      # Javascript
      {:esbuild, "~> 0.9", runtime: Mix.env() == :dev},
      {:dart_sass, "~> 0.7", runtime: Mix.env() == :dev},

      # Graphql
      {:absinthe, "~> 1.7"},
      {:absinthe_plug, "~> 1.5"},
      {:absinthe_phoenix, "~> 2.0"},

      # HTTP Client
      {:req, "~> 0.5"},
      {:floki, "~> 0.37"},

      # Language integration
      {:elixir_make, "~> 0.9", runtime: false},

      # P2P
      {:ranch, "~> 2.2"},
      {:mmdb2_decoder, "~> 3.0"},

      # Crypto
      {:plug_crypto, "~> 2.1", override: true},
      {:ex_keccak, "~> 0.7"},
      {:ex_secp256k1, "~> 0.7"},
      {:bls_ex, "~> 0.1"},

      # Numbering
      {:nx, "~> 0.9"},
      {:exla, "~> 0.9"},

      # WASM
      {:wasmex, "~> 0.11"},

      # Release
      {:distillery, github: "pasteque-org/distillery"},

      # Utils
      {:jason, "~> 1.0"},
      {:crontab, "~> 1.1"},
      {:earmark, "~> 1.4"},
      {:sizeable, "~> 1.0"},
      {:exjsonpath, "~> 0.9"},
      {:rand_compat, "~> 0.0.3"},
      {:gen_state_machine, "~> 3.0"},
      {:retry, "~> 0.19"},
      {:knigge, "~> 1.4"},
      {:ex_json_schema, "~> 0.11"},
      {:git_diff, "~> 0.6.4"},
      {:decimal, "~> 2.0"},
      {:ex_abi, "~> 0.8"},

      # Archethic Client
      {:archethic_client, github: "pasteque-org/libelixir", only: [:dev, :test]},

      # Monitoring
      {:observer_cli, "~> 1.8"},
      {:telemetry_metrics, "~> 1.1"},
      {:telemetry_metrics_prometheus_core, "~> 1.2"},
      {:telemetry_poller, "~> 1.2"},
      {:phoenix_live_dashboard, "~> 0.8"},

      # Benchmarks
      {:benchee, "~> 1.4", only: [:dev, :test]},
      {:benchee_html, "~> 1.0", only: :dev},

      # Documentation
      {:ex_doc, "~> 0.38", only: [:dev, :test], runtime: false},

      # Test
      {:mox, "~> 1.2", only: :test},
      {:mock, "~> 0.3", only: :test},
      {:stream_data, "~> 1.2", only: :test, runtime: false},
      {:gnuplot, "~> 1.22", only: :test, runtime: false},
      {:nimble_csv, "~> 1.1", only: :test, runtime: false},

      # Quality tools
      {:dialyxir, "~> 1.2", only: [:dev, :test], runtime: false},
      {:doctest_formatter, "~> 0.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.14", only: :dev, runtime: false},
      {:styler, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      "check.updates": ["cmd mix hex.outdated --within-requirements || echo 'Updates available!'"],
      "dev.update_deps": [
        "hex.outdated --within-requirements",
        "deps.update --all --only",
        "deps.clean --all --only",
        "deps.get",
        "deps.compile",
        "hex.outdated --within-requirements"
      ],
      # Intial developer Setup
      "dev.setup": ["deps.get", "cmd npm install --prefix assets"],
      # When Changes are not registered by compiler | any()
      "dev.clean": ["cmd make clean", "clean", "format", "compile"],
      # run single node
      "dev.run": ["deps.get", "cmd mix dev.clean", "cmd iex -S mix"],
      # Must be run before git push --no-verify | any(dialyzer issue)
      "dev.checks": [
        "clean",
        "format",
        "compile",
        " hex.outdated --within-requirements",
        "credo",
        "sobelow",
        "cmd mix test --trace",
        "dialyzer"
      ],
      # docker test-net with 3 nodes
      "dev.docker": [
        "cmd docker-compose down",
        "cmd docker build -t archethic-node .",
        "cmd docker-compose up"
      ],
      # benchmark
      "dev.bench": ["cmd docker-compose up bench"],
      # Cleans docker
      "dev.debug_docker": ["cmd docker-compose down", "cmd docker system prune -a"],
      # bench local
      "dev.lbench": ["cmd mix archethic.regression --bench localhost"],
      # production aliases
      "prod.run": ["cmd  MIX_ENV=prod ARCHETHIC_CRYPTO_NODE_KEYSTORE_IMPL=SOFTWARE
      ARCHETHIC_NODE_ALLOWED_KEY_ORIGINS=SOFTWARE ARCHETHIC_NODE_IP_VALIDATION='true' iex -S mix"],
      # dry-run,
      "run.dry": ["cmd iex -S mix run --no-start"],
      # Make sure the plts folder is created
      dialyzer: ["cmd mkdir -p priv/plts", "dialyzer"],
      "assets.sass": ["sass default --no-source-map --style=compressed"],
      "assets.deploy": [
        "esbuild default --minify",
        "phx.digest"
      ]
    ]
  end
end
