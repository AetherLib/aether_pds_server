# lib/aether_pds_server_web/plugs/require_auth.ex
defmodule AetherPDSServerWeb.Plugs.RequireAuth do
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        case AetherPDSServer.Token.verify_token(token) do
          {:ok, %{"sub" => did}} ->
            conn
            |> assign(:current_did, did)
            |> assign(:authenticated, true)

          {:error, _reason} ->
            conn
            |> add_cors_headers()
            |> put_status(:unauthorized)
            |> json(%{error: "AuthenticationRequired", message: "Valid authentication required"})
            |> halt()
        end

      _ ->
        conn
        |> add_cors_headers()
        |> put_status(:unauthorized)
        |> json(%{error: "AuthenticationRequired", message: "Valid authentication required"})
        |> halt()
    end
  end

  # Add CORS headers to error responses
  defp add_cors_headers(conn) do
    origin = get_req_header(conn, "origin") |> List.first() || "*"

    conn
    |> put_resp_header("access-control-allow-origin", origin)
    |> put_resp_header("access-control-allow-credentials", "true")
    |> put_resp_header("access-control-allow-methods", "GET, POST, PUT, DELETE, OPTIONS")
    |> put_resp_header(
      "access-control-allow-headers",
      "authorization, content-type, dpop, atproto-accept-labelers"
    )
    |> put_resp_header("access-control-max-age", "600")
  end
end
