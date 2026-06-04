# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :lbkmk,
  ecto_repos: [Lbkmk.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :lbkmk, LbkmkWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: LbkmkWeb.ErrorHTML, json: LbkmkWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Lbkmk.PubSub,
  live_view: [signing_salt: "SF3M5S0e"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
