# lib/aether_pds_server_web/controllers/server_controller.ex
defmodule AetherPDSServerWeb.ServerController do
  use AetherPDSServerWeb, :controller

  alias AetherPDSServer.{Accounts, OAuth}

  @doc """
  GET /xrpc/com.atproto.server.describeServer

  Returns server metadata and capabilities
  """
  def describe_server(conn, _params) do
    response = %{
      availableUserDomains: [".bsky.social"],
      inviteCodeRequired: false,
      links: %{
        privacyPolicy: "https://example.com/privacy",
        termsOfService: "https://example.com/terms"
      }
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

      response = %{
        accessJwt: access_token,
        refreshJwt: refresh_token,
        handle: account.handle,
        did: account.did,
        didDoc: nil
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

        response = %{
          accessJwt: access_token,
          refreshJwt: refresh_token,
          handle: account.handle,
          did: account.did,
          didDoc: nil
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
            response = %{
              accessJwt: new_access_token,
              refreshJwt: new_refresh_token,
              handle: account.handle,
              did: account.did,
              didDoc: nil
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
        response = %{
          handle: account.handle,
          did: account.did,
          didDoc: nil,
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

  # Helper functions

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
