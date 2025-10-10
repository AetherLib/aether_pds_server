import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :aether_pds_server, AetherPDSServer.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "aether_pds_server_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :aether_pds_server, AetherPDSServerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "R1ZUGUrhaYPKz4FT+4830JqmgQRjAm5MK9IyrY39NzZyBESgbdQrYl1r02m7rrES",
  server: false

# In test we don't send emails
config :aether_pds_server, AetherPDSServer.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# # Configure MinIO for testing (using credentials from .env)
# config :aether_pds_server, :minio,
#   endpoint: "http://localhost:9002",
#   bucket: "blob",
#   access_key_id: "TncEgp5sZoqivi1b7593",
#   secret_access_key: "CFUxFp4nx8vn0hblUngxzrQYETDuVbHgOtaSx5Pa",
#   region: "us-east-1"
