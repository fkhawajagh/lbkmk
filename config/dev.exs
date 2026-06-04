import Config

config :lbkmk, Lbkmk.Repo,
  username: "lbkmk",
  password: "lbkmk",
  hostname: "localhost",
  database: "lbkmk_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :lbkmk, LbkmkWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "O1ogkifJMe7V/yYLZF5xyH6WIEk0Fr+eftZxcmCbrUV4E0h/L47rEU6QV9jTrUmj",
  watchers: []

config :lbkmk, dev_routes: true

config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  debug_heex_annotations: true,
  debug_attributes: true,
  enable_expensive_runtime_checks: true
