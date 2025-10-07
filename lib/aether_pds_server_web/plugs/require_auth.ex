# lib/aether_pds_server_web/plugs/require_auth.ex
defmodule AetherPDSServerWeb.Plugs.RequireAuth do
  @moduledoc """
  Authentication plug that validates access tokens.

  Supports two modes:
  1. Simple mode (for testing): Validates token without DPoP
  2. DPoP mode (production): Requires DPoP proof with token
  """
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        # Extract DPoP proof if present
        dpop_proof = get_req_header(conn, "dpop") |> List.first()

        # Try simple validation first (for tokens created by ServerController)
        case validate_simple_token(token) do
          {:ok, did} ->
            conn
            |> assign(:current_did, did)
            |> assign(:authenticated, true)

          {:error, :not_simple_token} ->
            # Fall back to DPoP validation
            validate_dpop_token(conn, token, dpop_proof)
        end

      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "AuthenticationRequired", message: "Valid authentication required"})
        |> halt()
    end
  end

  defp validate_simple_token(token) do
    # Check if this is a simple token (stored in access_tokens with dummy DPoP)
    case AetherPDSServer.OAuth.get_simple_access_token(token) do
      {:ok, did} -> {:ok, did}
      _ -> {:error, :not_simple_token}
    end
  end

  defp validate_dpop_token(conn, token, dpop_proof) do
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
  end
end
