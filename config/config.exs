# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :aether_pds_server,
  ecto_repos: [AetherPDSServer.Repo],
  generators: [timestamp_type: :utc_datetime],
  # HTTP client options for DID resolution
  req_options: [
    connect_options: [timeout: 5_000],
    receive_timeout: 10_000,
    retry: :transient,
    max_retries: 2
  ]

# Configures the endpoint
config :aether_pds_server, AetherPDSServerWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: AetherPDSServerWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: AetherPDSServer.PubSub,
  live_view: [signing_salt: "lj3wDXBM"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :aether_pds_server, AetherPDSServer.Mailer, adapter: Swoosh.Adapters.Local

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  aether_pds_server: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
