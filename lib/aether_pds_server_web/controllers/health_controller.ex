# lib/aether_pds_server_web/controllers/health_controller.ex
defmodule AetherPDSServerWeb.HealthController do
  use AetherPDSServerWeb, :controller

  @doc """
  GET /_health
  GET /xrpc/_health

  Health check endpoint
  """
  def index(conn, _params) do
    # Check database connection
    db_status =
      try do
        AetherPDSServer.Repo.query!("SELECT 1")
        "healthy"
      rescue
        _ -> "unhealthy"
      end

    response = %{
      status: if(db_status == "healthy", do: "ok", else: "error"),
      version: Application.spec(:aether_pds_server, :vsn) |> to_string(),
      database: db_status
    }

    status_code = if db_status == "healthy", do: :ok, else: :service_unavailable

    conn
    |> put_status(status_code)
    |> json(response)
  end
end
