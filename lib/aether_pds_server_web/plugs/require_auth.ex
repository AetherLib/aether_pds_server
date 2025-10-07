# lib/aether_pds_server_web/plugs/require_auth.ex
defmodule AetherPDSServerWeb.Plugs.RequireAuth do
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        case verify_token(token) do
          {:ok, did} ->
            conn
            |> assign(:current_did, did)
            |> assign(:authenticated, true)

          {:error, _reason} ->
            conn
            |> put_status(:unauthorized)
            |> json(%{error: "AuthenticationRequired", message: "Valid authentication required"})
            |> halt()
        end

      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "AuthenticationRequired", message: "Valid authentication required"})
        |> halt()
    end
  end

  defp verify_token(token) do
    # TODO: Implement JWT verification
    # For now, placeholder
    {:error, :not_implemented}
  end
end
