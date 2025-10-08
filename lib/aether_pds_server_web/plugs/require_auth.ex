# lib/aether_pds_server_web/plugs/require_auth.ex
defmodule AetherPDSServerWeb.Plugs.RequireAuth do
  import Plug.Conn
  import Phoenix.Controller
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        case AetherPDSServer.Token.verify_token(token) do
          {:ok, claims} ->
            did = claims["sub"]

            conn
            |> assign(:current_did, did)
            |> assign(:authenticated, true)

          {:error, reason} ->
            send_auth_error(conn)
        end

      _ ->
        send_auth_error(conn)
    end
  end

  defp send_auth_error(conn) do
    conn
    |> put_resp_header("access-control-allow-origin", get_origin(conn))
    |> put_resp_header("access-control-allow-credentials", "true")
    |> put_status(:unauthorized)
    |> json(%{error: "AuthenticationRequired", message: "Valid authentication required"})
    |> halt()
  end

  defp get_origin(conn) do
    case get_req_header(conn, "origin") do
      [origin] -> origin
      [] -> "*"
    end
  end
end
