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
  GET /.well-known/did.json

  Serve the DID document for did:web resolution. This endpoint is called
  when resolving a did:web DID like did:web:alice.aetherlib.org

  The OAuth client will fetch https://alice.aetherlib.org/.well-known/did.json
  to resolve the DID document.
  """
  def well_known_did_json(conn, _params) do
    # Get the host from the request (e.g., "alice.aetherlib.org")
    host = conn.host

    # Look up the account by handle
    case Accounts.get_account_by_handle(host) do
      %{did: did, handle: handle} = account ->
        # Get the PDS endpoint from the application config
        pds_endpoint = AetherPDSServerWeb.Endpoint.url()

        # Get the public key for the account (you'll need to implement this)
        case get_account_public_key(account) do
          {:ok, public_key_multibase} ->
            # Generate the compliant DID document
            did_doc = %{
              "@context" => [
                "https://www.w3.org/ns/did/v1",
                "https://w3id.org/security/multikey/v1"
              ],
              "id" => did,
              "alsoKnownAs" => ["at://#{handle}"],
              "verificationMethod" => [
                %{
                  "id" => "#{did}#atproto",
                  "type" => "Multikey",
                  "controller" => did,
                  "publicKeyMultibase" => public_key_multibase
                }
              ],
              "service" => [
                %{
                  "id" => "#{did}#atproto_pds",
                  "type" => "AtprotoPersonalDataServer",
                  "serviceEndpoint" => pds_endpoint
                }
              ]
            }

            json(conn, did_doc)

          {:error, :public_key_not_found} ->
            conn
            |> put_status(:internal_server_error)
            |> json(%{
              error: "ConfigurationError",
              message: "Public key not configured for account"
            })
        end

      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "NotFound", message: "Handle not found"})
    end
  end

  @doc """
  GET /xrpc/com.atproto.identity.resolveHandle

  Resolve a handle to a DID (local or remote) with bidirectional validation
  """
  def resolve_handle(conn, %{"handle" => handle}) do
    # Validate handle format first
    if not valid_handle?(handle) do
      handle_error(conn, :bad_request, "InvalidHandle", "Invalid handle format")
    else
      # Try local resolution first
      case Accounts.get_account_by_handle(handle) do
        %{did: did} ->
          json(conn, %{did: did})

        nil ->
          # Try remote resolution via DIDResolver
          case DIDResolver.resolve_handle(handle) do
            {:ok, remote_did} ->
              # Perform bidirectional validation
              case validate_handle_bidirectional(handle, remote_did) do
                {:ok, true} ->
                  json(conn, %{did: remote_did})

                {:ok, false} ->
                  handle_error(
                    conn,
                    :not_found,
                    "HandleNotFound",
                    "Handle not confirmed by DID document"
                  )

                {:error, reason} ->
                  handle_error(
                    conn,
                    :bad_request,
                    "ResolutionError",
                    "Failed to validate handle: #{reason}"
                  )
              end

            {:error, :handle_resolution_failed} ->
              handle_error(conn, :not_found, "HandleNotFound", "Handle not found")

            {:error, reason} ->
              handle_error(
                conn,
                :bad_request,
                "InvalidRequest",
                "Failed to resolve handle: #{reason}"
              )
          end
      end
    end
  end

  @doc """
  GET /xrpc/com.atproto.identity.resolveDid

  Resolve a DID to a DID document
  """
  def resolve_did(conn, %{"did" => did}) do
    # Validate DID format
    if not valid_did?(did) do
      handle_error(conn, :bad_request, "InvalidDID", "Invalid DID format")
    else
      case DIDResolver.resolve_did(did) do
        {:ok, did_doc} ->
          json(conn, did_doc)

        {:error, :did_resolution_failed} ->
          handle_error(conn, :not_found, "DIDNotFound", "DID not found")

        {:error, :unsupported_did_method} ->
          handle_error(conn, :bad_request, "UnsupportedDIDMethod", "DID method not supported")

        {:error, reason} ->
          handle_error(conn, :bad_request, "InvalidRequest", "Failed to resolve DID: #{reason}")
      end
    end
  end

  defp get_account_public_key(account) do
    # You need to implement this function based on your key management
    # This should return the public key in multibase format
    # Example implementation:
    case Accounts.get_public_signing_key(account) do
      nil -> {:error, :public_key_not_found}
      public_key -> {:ok, public_key}
    end

    # If you don't have key management implemented yet, you can use this placeholder:
    # {:ok, "z" <> Base.encode64(:crypto.strong_rand_bytes(32))}
  end

  defp validate_handle_bidirectional(handle, did) do
    # Resolve the DID to get its document
    case DIDResolver.resolve_did(did) do
      {:ok, did_document} ->
        # Check if the handle appears in the alsoKnownAs array
        is_valid = handle_in_also_known_as?(did_document, handle)
        {:ok, is_valid}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_in_also_known_as?(%{"alsoKnownAs" => also_known_as}, handle)
       when is_list(also_known_as) do
    expected_handle_uri = "at://#{handle}"
    Enum.any?(also_known_as, fn uri -> uri == expected_handle_uri end)
  end

  defp handle_in_also_known_as?(_, _), do: false

  defp valid_handle?(handle) do
    # Basic handle validation - you might want to enhance this
    is_binary(handle) and String.length(handle) > 0 and String.length(handle) <= 253 and
      String.match?(handle, ~r/^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/)
  end

  defp valid_did?(did) do
    # Basic DID validation
    is_binary(did) and String.match?(did, ~r/^did:[a-z0-9]+:[a-zA-Z0-9._:%-]+$/)
  end

  defp handle_error(conn, status, error_type, message) do
    conn
    |> put_status(status)
    |> json(%{error: error_type, message: message})
  end
end
