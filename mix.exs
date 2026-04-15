defmodule EcoSyncBackend.MixProject do
  use Mix.Project

  def project do
    [
      app: :eco_sync_backend,
      version: "1.0.0",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      docs: docs(),
      reviewers: ["TFariasMath"],
      licenses: ["MPL-2.0"],
      links: %{
        "Changelog" => "https://github.com/TFariasMath/eco-sync-backend/blob/main/CHANGELOG.md",
        "License" => "https://github.com/TFariasMath/eco-sync-backend/blob/main/LICENSE"
      }
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {EcoSyncBackend.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp docs do
    [
      main: "EcoSyncBackend",
      source_ref: "v1.0.0",
      source_url: "https://github.com/TFariasMath/eco-sync-backend",
      extras: ["CHANGELOG.md", "LICENSE", "LICENSE-DOCS", "README.md"]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.5"},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:req, "~> 0.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:bandit, "~> 1.5"},
      {:cors_plug, "~> 3.0"},

      # Dev and test dependencies
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:mix_test_watch, "~> 1.0", only: :dev, runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get"],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
