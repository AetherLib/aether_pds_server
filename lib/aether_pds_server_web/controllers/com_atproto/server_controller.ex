# lib/aether_pds_server_web/controllers/server_controller.ex
defmodule AetherPDSServerWeb.ComATProto.ServerController do
  use AetherPDSServerWeb, :controller

  alias AetherPDSServer.{Accounts, OAuth}

  @doc """
  GET /xrpc/com.atproto.server.describeServer

  Returns server metadata and capabilities
  """
  def describe_server(conn, _params) do
    base_url = AetherPDSServerWeb.Endpoint.url()

    response = %{
      # Users on this PDS will have handles like: alice.pds.aetherlib.org
      availableUserDomains: ["pds.aetherlib.org"],

      # Set to true if you want invite-only registration
      inviteCodeRequired: false,

      # Your PDS details
      links: %{
        privacyPolicy: "https://pds.aetherlib.org/privacy",
        termsOfService: "https://pds.aetherlib.org/terms"
      },

      # Optional: Contact information
      contact: %{
        email: "hello@fullstack.ing"
      },

      # DID of the server itself (optional but recommended)
      did: "did:web:pds.aetherlib.org",

      # OAuth authorization servers (tells clients to use OAuth instead of legacy auth)
      authorizationServers: [base_url]
    }

    json(conn, response)
  end

  @doc """
  POST /xrpc/com.atproto.server.createAccount

  Create a new account on this PDS
  """
  def create_account(conn, params) do
    with {:ok, validated_params} <- validate_create_account_params(params),
         {:ok, account} <- Accounts.create_account(validated_params) do
      # Create initial session tokens
      {:ok, access_token} = Accounts.create_access_token(account.did)
      {:ok, refresh_token} = Accounts.create_refresh_token(account.did)

      did_doc = build_did_document(account.did, account.handle)

      response = %{
        accessJwt: access_token,
        refreshJwt: refresh_token,
        handle: account.handle,
        did: account.did,
        didDoc: did_doc
      }

      json(conn, response)
    else
      {:error, :handle_taken} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "HandleNotAvailable", message: "Handle is already taken"})

      {:error, :invalid_handle} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "InvalidHandle", message: "Handle format is invalid"})

      {:error, :missing_params} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "InvalidRequest", message: "Missing required parameters"})

      {:error, changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "InvalidRequest", message: format_errors(changeset)})
    end
  end

  @doc """
  POST /xrpc/com.atproto.server.createSession

  Create a new session (login)
  """
  def create_session(conn, %{"identifier" => identifier, "password" => password}) do
    case Accounts.authenticate(identifier, password) do
      {:ok, account} ->
        {:ok, access_token} = Accounts.create_access_token(account.did)
        {:ok, refresh_token} = Accounts.create_refresh_token(account.did)
        did_doc = build_did_document(account.did, account.handle)

        response = %{
          accessJwt: access_token,
          refreshJwt: refresh_token,
          handle: account.handle,
          did: account.did,
          didDoc: did_doc
        }

        json(conn, response)

      {:error, :invalid_credentials} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "AuthenticationFailed", message: "Invalid credentials"})
    end
  end

  @doc """
  POST /xrpc/com.atproto.server.refreshSession

  Refresh an access token using a refresh token
  """
  def refresh_session(conn, _params) do
    # Extract refresh token from Authorization header
    case get_req_header(conn, "authorization") do
      ["Bearer " <> refresh_token] ->
        case Accounts.refresh_session(refresh_token) do
          {:ok, account, new_access_token, new_refresh_token} ->
            did_doc = build_did_document(account.did, account.handle)

            response = %{
              accessJwt: new_access_token,
              refreshJwt: new_refresh_token,
              handle: account.handle,
              did: account.did,
              didDoc: did_doc
            }

            json(conn, response)

          {:error, :invalid_token} ->
            conn
            |> put_status(:unauthorized)
            |> json(%{error: "InvalidToken", message: "Refresh token is invalid or expired"})
        end

      _ ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "InvalidRequest", message: "Refresh token required"})
    end
  end

  @doc """
  GET /xrpc/com.atproto.server.getSession

  Get current session info
  """
  def get_session(conn, _params) do
    did = conn.assigns[:current_did]

    case Accounts.get_account_by_did(did) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "AccountNotFound", message: "Account not found"})

      account ->
        did_doc = build_did_document(account.did, account.handle)

        response = %{
          handle: account.handle,
          did: account.did,
          didDoc: did_doc,
          email: account.email
        }

        json(conn, response)
    end
  end

  @doc """
  POST /xrpc/com.atproto.server.deleteSession

  Delete current session (logout)
  """
  def delete_session(conn, _params) do
    did = conn.assigns[:current_did]

    # Revoke all tokens for this DID
    OAuth.revoke_all_tokens_for_did(did)

    json(conn, %{})
  end

  @doc """
  POST /xrpc/com.atproto.server.createAppPassword

  Create an app-specific password for the authenticated user
  """
  def create_app_password(conn, %{"name" => name} = params) do
    did = conn.assigns[:current_did]

    case Accounts.get_account_by_did(did) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "AccountNotFound", message: "Account not found"})

      account ->
        attrs = %{
          name: name,
          privileged: Map.get(params, "privileged", false)
        }

        case Accounts.create_app_password(account.id, attrs) do
          {:ok, app_password} ->
            response = %{
              name: app_password.name,
              password: app_password.password,
              createdAt: DateTime.to_iso8601(app_password.created_at),
              privileged: app_password.privileged
            }

            json(conn, response)

          {:error, changeset} ->
            conn
            |> put_status(:bad_request)
            |> json(%{error: "InvalidRequest", message: format_errors(changeset)})
        end
    end
  end

  def create_app_password(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "InvalidRequest", message: "Missing required parameter: name"})
  end

  @doc """
  GET /xrpc/com.atproto.server.listAppPasswords

  List all app passwords for the authenticated user
  """
  def list_app_passwords(conn, _params) do
    did = conn.assigns[:current_did]

    case Accounts.get_account_by_did(did) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "AccountNotFound", message: "Account not found"})

      account ->
        passwords = Accounts.list_app_passwords(account.id)

        response = %{
          passwords:
            Enum.map(passwords, fn pw ->
              %{
                name: pw.name,
                createdAt: DateTime.to_iso8601(pw.created_at),
                privileged: pw.privileged
              }
            end)
        }

        json(conn, response)
    end
  end

  @doc """
  POST /xrpc/com.atproto.server.revokeAppPassword

  Revoke an app password by name
  """
  def revoke_app_password(conn, %{"name" => name}) do
    did = conn.assigns[:current_did]

    case Accounts.get_account_by_did(did) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "AccountNotFound", message: "Account not found"})

      account ->
        case Accounts.revoke_app_password(account.id, name) do
          {:ok, _} ->
            json(conn, %{})

          {:error, :not_found} ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "NotFound", message: "App password not found"})

          {:error, _reason} ->
            conn
            |> put_status(:internal_server_error)
            |> json(%{error: "InternalServerError", message: "Failed to revoke app password"})
        end
    end
  end

  def revoke_app_password(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "InvalidRequest", message: "Missing required parameter: name"})
  end

  @doc """
  POST /xrpc/com.atproto.server.deactivateAccount

  Deactivate the authenticated user's account
  """
  def deactivate_account(conn, _params) do
    did = conn.assigns[:current_did]

    case Accounts.deactivate_account(did) do
      {:ok, _account} ->
        json(conn, %{})

      {:error, :account_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "AccountNotFound", message: "Account not found"})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "InvalidRequest", message: inspect(reason)})
    end
  end

  @doc """
  POST /xrpc/com.atproto.server.activateAccount

  Activate a previously deactivated account
  """
  def activate_account(conn, _params) do
    did = conn.assigns[:current_did]

    case Accounts.activate_account(did) do
      {:ok, _account} ->
        json(conn, %{})

      {:error, :account_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "AccountNotFound", message: "Account not found"})

      {:error, :account_deleted} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "AccountDeleted", message: "Cannot reactivate a deleted account"})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "InvalidRequest", message: inspect(reason)})
    end
  end

  @doc """
  POST /xrpc/com.atproto.server.deleteAccount

  Permanently delete the authenticated user's account
  """
  def delete_account(conn, %{"did" => did, "password" => password, "token" => _token}) do
    current_did = conn.assigns[:current_did]

    # Verify the DID matches the authenticated user
    if did != current_did do
      conn
      |> put_status(:forbidden)
      |> json(%{error: "Forbidden", message: "Cannot delete another user's account"})
    else
      case Accounts.delete_account(did, password) do
        {:ok, _account} ->
          # Revoke all tokens for this DID
          OAuth.revoke_all_tokens_for_did(did)

          json(conn, %{})

        {:error, :account_not_found} ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "AccountNotFound", message: "Account not found"})

        {:error, :invalid_password} ->
          conn
          |> put_status(:unauthorized)
          |> json(%{error: "AuthenticationFailed", message: "Invalid password"})

        {:error, reason} ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "InvalidRequest", message: inspect(reason)})
      end
    end
  end

  def delete_account(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      error: "InvalidRequest",
      message: "Missing required parameters: did, password, token"
    })
  end

  @doc """
  POST /xrpc/com.atproto.server.requestAccountDelete

  Request an account deletion token (simplified - no email)
  """
  def request_account_delete(conn, _params) do
    # In the official implementation, this would:
    # 1. Generate a deletion token
    # 2. Send it via email
    #
    # Since we're skipping email functionality, we'll return a simple response
    # indicating the request was received but email features are not implemented

    conn
    |> put_status(:not_implemented)
    |> json(%{
      error: "NotImplemented",
      message:
        "Account deletion requires email verification which is not yet implemented. Please contact an administrator."
    })
  end

  @doc """
  GET /xrpc/com.atproto.server.getServiceAuth

  Get a service authentication token for inter-service communication
  """
  def get_service_auth(conn, %{"aud" => audience, "lxm" => _lexicon_method} = params) do
    did = conn.assigns[:current_did]
    exp_seconds = params["exp"]

    # Validate expiration if provided
    exp =
      if exp_seconds do
        case Integer.parse(exp_seconds) do
          {exp_int, ""} when exp_int > 0 and exp_int <= 648_000 ->
            exp_int

          _ ->
            # Invalid expiration, return error
            conn
            |> put_status(:bad_request)
            |> json(%{
              error: "InvalidRequest",
              message: "Invalid expiration value. Must be between 1 and 648000 seconds (7.5 days)"
            })
            |> halt()
        end
      else
        # Default to 5 minutes (300 seconds)
        300
      end

    # Check if connection was halted by validation
    if conn.halted do
      conn
    else
      case Accounts.get_account_by_did(did) do
        nil ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "AccountNotFound", message: "Account not found"})

        account ->
          # Check if account is deleted/deactivated
          if account.status != "active" do
            conn
            |> put_status(:forbidden)
            |> json(%{
              error: "AccountNotActive",
              message: "Cannot generate service auth for inactive account"
            })
          else
            # Generate service JWT token
            case generate_service_token(did, audience, exp) do
              {:ok, token} ->
                json(conn, %{token: token})

              {:error, reason} ->
                conn
                |> put_status(:internal_server_error)
                |> json(%{
                  error: "InternalServerError",
                  message: "Failed to generate service token: #{inspect(reason)}"
                })
            end
          end
      end
    end
  end

  def get_service_auth(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      error: "InvalidRequest",
      message: "Missing required parameters: aud (audience) and lxm (lexicon method)"
    })
  end

  @doc """
  POST /xrpc/com.atproto.server.reserveSigningKey

  Reserve a signing key for the authenticated user's DID
  """
  def reserve_signing_key(conn, _params) do
    did = conn.assigns[:current_did]

    case Accounts.get_account_by_did(did) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "AccountNotFound", message: "Account not found"})

      _account ->
        {:ok, signing_key} = generate_signing_keypair()
        json(conn, %{signingKey: signing_key})
    end
  end

  # Helper functions

  defp generate_service_token(did, audience, exp_seconds) do
    # Generate a JWT token for service-to-service authentication
    now = System.system_time(:second)
    exp = now + exp_seconds

    claims = %{
      "iss" => did,
      "aud" => audience,
      "exp" => exp,
      "iat" => now
    }

    # Use the same token generation as access tokens
    AetherPDSServer.Token.generate_service_token(claims)
  end

  defp generate_signing_keypair do
    # Generate a secp256k1 keypair for signing
    # In production, this would use proper crypto libraries
    # For now, we'll generate a placeholder key

    # Generate random private key (32 bytes)
    private_key = :crypto.strong_rand_bytes(32)

    # Encode as base64
    signing_key = Base.encode64(private_key)

    {:ok, signing_key}
  end

  defp validate_create_account_params(params) do
    required = ["handle", "email", "password"]

    if Enum.all?(required, &Map.has_key?(params, &1)) do
      {:ok,
       %{
         handle: params["handle"],
         email: params["email"],
         password: params["password"],
         inviteCode: params["inviteCode"]
       }}
    else
      {:error, :missing_params}
    end
  end

  # Add this helper function
  defp build_did_document(did, handle) do
    pds_url = AetherPDSServerWeb.Endpoint.url()

    %{
      "@context" => [
        "https://www.w3.org/ns/did/v1",
        "https://w3id.org/security/multikey/v1",
        "https://w3id.org/security/suites/secp256k1-2019/v1"
      ],
      "id" => did,
      "alsoKnownAs" => ["at://#{handle}"],
      "verificationMethod" => [],
      "service" => [
        %{
          "id" => "#atproto_pds",
          "type" => "AtprotoPersonalDataServer",
          "serviceEndpoint" => pds_url
        }
      ]
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
    |> Enum.join("; ")
  end
end
