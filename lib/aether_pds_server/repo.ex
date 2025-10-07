defmodule AetherPdsServer.Repo do
  use Ecto.Repo,
    otp_app: :aether_pds_server,
    adapter: Ecto.Adapters.Postgres
end
