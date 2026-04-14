# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :eco_sync_backend,
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :eco_sync_backend, EcoSyncBackendWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: EcoSyncBackendWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: EcoSyncBackend.PubSub,
  live_view: [signing_salt: "5SVmyx2Y"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :eco_sync_backend, EcoSyncBackend.Mailer, adapter: Swoosh.Adapters.Local

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Ueberauth configuration
config :ueberauth, Ueberauth,
  providers: [
    github: {Ueberauth.Strategy.Github, [default_scope: "repo,delete_repo"]},
    google: {Ueberauth.Strategy.Google, [default_scope: "https://www.googleapis.com/auth/drive.metadata.readonly https://www.googleapis.com/auth/drive.file"]}
  ]

config :ueberauth, Ueberauth.Strategy.Github.OAuth,
  client_id: {:system, "GITHUB_CLIENT_ID"},
  client_secret: {:system, "GITHUB_CLIENT_SECRET"}

config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  client_id: {:system, "GOOGLE_CLIENT_ID"},
  client_secret: {:system, "GOOGLE_CLIENT_SECRET"},
  redirect_uri: {:system, "GOOGLE_REDIRECT_URI"}

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
