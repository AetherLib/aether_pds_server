# lib/aether_pds_server_web/controllers/identity_controller.ex
defmodule AetherPDSServerWeb.ComATProto.IdentityController do
  use AetherPDSServerWeb, :controller

  alias AetherPDSServer.Accounts
  alias AetherPDSServer.DIDResolver

  @doc """
  GET /.well-known/atproto-did

  Serve the DID for handle-based resolution. This is called when someone
  visits https://[handle]/.well-known/atproto-did to verify handle ownership.
  The response should be plain text containing just the DID.

  Supports both:
  - Direct domain: somehandle.com -> looks up "somehandle.com"
  - Subdomain: somehandle.aetherlib.org -> looks up "somehandle.aetherlib.org"
  """
  def well_known_did(conn, _params) do
    # Get the host from the request (e.g., "somehandle.aetherlib.org")
    host = conn.host

    # The full host IS the handle in ATProto (handles are full domain names)
    # For example: "alice.bsky.social" or "alice.aetherlib.org"
    case Accounts.get_account_by_handle(host) do
      %{did: did} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(200, did)

      nil ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(404, "Handle not found")
    end
  end

  @doc """
  GET /xrpc/com.atproto.identity.resolveHandle

  Resolve a handle to a DID (local or remote)
  """
  def resolve_handle(conn, %{"handle" => handle}) do
    # Try local resolution first
    case Accounts.get_account_by_handle(handle) do
      %{did: did} ->
        json(conn, %{did: did})

      nil ->
        # Try remote resolution via DIDResolver
        case DIDResolver.resolve_handle(handle) do
          {:ok, did} ->
            json(conn, %{did: did})

          {:error, :handle_resolution_failed} ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "HandleNotFound", message: "Handle not found"})

          {:error, _reason} ->
            conn
            |> put_status(:bad_request)
            |> json(%{error: "InvalidRequest", message: "Failed to resolve handle"})
        end
    end
  end

  @doc """
  GET /xrpc/com.atproto.identity.resolveDid

  Resolve a DID to a DID document
  """
  def resolve_did(conn, %{"did" => did}) do
    case DIDResolver.resolve_did(did) do
      {:ok, did_doc} ->
        json(conn, did_doc)

      {:error, :did_resolution_failed} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "DIDNotFound", message: "DID not found"})

      {:error, :unsupported_did_method} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "UnsupportedDIDMethod", message: "DID method not supported"})

      {:error, _reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "InvalidRequest", message: "Failed to resolve DID"})
    end
  end
end
