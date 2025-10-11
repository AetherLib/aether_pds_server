# lib/aether_pds_server_web/plugs/require_auth.ex
defmodule AetherPDSServerWeb.Plugs.RequireAuth do
  import Plug.Conn
  import Phoenix.Controller
  require Logger

  alias AetherPDSServer.OAuth

  def init(opts), do: opts

  def call(conn, _opts) do
    auth_header = get_req_header(conn, "authorization") |> List.first()
    dpop_header = get_req_header(conn, "dpop") |> List.first()

    Logger.info("Auth attempt - Authorization: #{inspect(auth_header)}, DPoP: #{inspect(dpop_header)}")

    case auth_header do
      # DPoP-bound token (OAuth flow)
      "DPoP " <> token when not is_nil(dpop_header) ->
        method = conn.method
        url = build_request_url(conn)
        Logger.info("DPoP validation - Method: #{method}, URL: #{url}")

        case OAuth.validate_access_token(token, dpop_header, method, url) do
          {:ok, token_data} ->
            conn
            |> assign(:current_did, token_data.did)
            |> assign(:authenticated, true)

          {:error, reason} ->
            Logger.info("DPoP token validation failed: #{inspect(reason)}")
            send_auth_error(conn)
        end

      # Legacy Bearer token (simple JWT - for backwards compatibility)
      "Bearer " <> token ->
        case AetherPDSServer.Token.verify_token(token) do
          {:ok, claims} ->
            did = claims["sub"]

            conn
            |> assign(:current_did, did)
            |> assign(:authenticated, true)

          {:error, _reason} ->
            send_auth_error(conn)
        end

      _ ->
        Logger.info("No valid authorization header found")
        send_auth_error(conn)
    end
  end

  defp build_request_url(conn) do
    scheme = if conn.scheme == :https, do: "https", else: "http"
    host = conn.host
    port = conn.port

    port_suffix =
      cond do
        scheme == "https" and port == 443 -> ""
        scheme == "http" and port == 80 -> ""
        true -> ":#{port}"
      end

    path = conn.request_path
    query = if conn.query_string != "", do: "?#{conn.query_string}", else: ""

    "#{scheme}://#{host}#{port_suffix}#{path}#{query}"
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
