# lib/aether_pds_server_web/plugs/require_auth.ex
defmodule AetherPDSServerWeb.Plugs.RequireAuth do
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        # Extract DPoP proof if present
        dpop_proof = get_req_header(conn, "dpop") |> List.first()

        case AetherPDSServer.OAuth.validate_access_token(
               token,
               dpop_proof,
               conn.method,
               conn.request_path
             ) do
          {:ok, %{did: did}} ->
            conn
            |> assign(:current_did, did)
            |> assign(:authenticated, true)

          {:error, :invalid_token} ->
            conn
            |> put_status(:unauthorized)
            |> json(%{error: "AuthenticationRequired", message: "Valid authentication required"})
            |> halt()

          {:error, :missing_dpop_proof} ->
            conn
            |> put_status(:unauthorized)
            |> json(%{error: "DPoPRequired", message: "DPoP proof required for this token"})
            |> halt()

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
end
