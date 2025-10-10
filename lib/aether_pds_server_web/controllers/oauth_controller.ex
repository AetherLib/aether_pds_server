defmodule AetherPDSServerWeb.OAuthController do
  @moduledoc """
  OAuth 2.1 + DPoP Authorization Server implementation for AT Protocol.

  This PDS acts as the authorization server, issuing tokens to client applications.
  """
  use AetherPDSServerWeb, :controller

  alias AetherPDSServer.{Accounts, OAuth}
  require Logger

  # ============================================================================
  # OAuth Server Metadata
  # ============================================================================

  @doc """
  GET /.well-known/oauth-authorization-server

  Returns OAuth server metadata (RFC 8414)
  """
  def metadata(conn, _params) do
    base_url = AetherPDSServerWeb.Endpoint.url()

    metadata = %{
      issuer: base_url,
      authorization_endpoint: "#{base_url}/oauth/authorize",
      token_endpoint: "#{base_url}/oauth/token",
      response_types_supported: ["code"],
      grant_types_supported: ["authorization_code", "refresh_token"],
      code_challenge_methods_supported: ["S256"],
      token_endpoint_auth_methods_supported: ["none"],
      dpop_signing_alg_values_supported: ["ES256"],
      scopes_supported: ["atproto", "transition:generic", "transition:chat.bsky"],
      authorization_response_iss_parameter_supported: true,
      require_pushed_authorization_requests: false
    }

    json(conn, metadata)
  end

  # ============================================================================
  # Authorization Flow
  # ============================================================================

  @doc """
  GET /oauth/authorize

  Authorization endpoint - displays consent screen or login
  """
  def authorize(conn, params) do
    with {:ok, validated_params} <- validate_authorization_params(params),
         {:ok, client} <-
           OAuth.validate_client(
             validated_params.client_id,
             validated_params.redirect_uri
           ),
         :ok <-
           validate_pkce(validated_params.code_challenge, validated_params.code_challenge_method) do
      # Check if user is already logged in
      case get_session(conn, :user_did) do
        nil ->
          # Show login page with authorization request stored in session
          conn
          |> put_session(:oauth_request, validated_params)
          |> redirect(to: "/oauth/login?client_id=#{URI.encode_www_form(client.name)}")

        user_did ->
          # User logged in - show consent screen
          user = Accounts.get_user_by_did!(user_did)

          conn
          |> put_session(:oauth_request, validated_params)
          |> render_consent_page(user, client, validated_params)
      end
    else
      {:error, :invalid_client} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          error: "invalid_client",
          error_description: "Invalid client_id or redirect_uri"
        })

      {:error, :invalid_request} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid_request", error_description: "Missing or invalid parameters"})

      {:error, reason} ->
        Logger.error("Authorization request failed: #{inspect(reason)}")

        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid_request", error_description: "Authorization request failed"})
    end
  end

  @doc """
  GET /oauth/login

  Login page for OAuth flow
  """
  def login_page(conn, params) do
    client_name = Map.get(params, "client_id", "Unknown Application")
    error = Phoenix.Flash.get(conn.assigns.flash, :error)

    # Render login page
    conn
    |> put_view(AetherPDSServerWeb.OAuthHTML)
    |> put_layout(false)
    |> render(:login, client_name: client_name, error: error)
  end

  @doc """
  POST /oauth/login

  Handle login submission
  """
  def login(conn, %{"handle" => handle, "password" => password}) do
    case Accounts.authenticate_user(handle, password) do
      {:ok, user} ->
        oauth_request = get_session(conn, :oauth_request)

        if oauth_request do
          # Redirect back to authorization with logged in user
          # The oauth_request is already in session, so we can just redirect back with the original params
          query_params = %{
            "response_type" => oauth_request.response_type,
            "client_id" => oauth_request.client_id,
            "redirect_uri" => oauth_request.redirect_uri,
            "state" => oauth_request.state,
            "code_challenge" => oauth_request.code_challenge,
            "code_challenge_method" => oauth_request.code_challenge_method,
            "scope" => oauth_request.scope
          }

          conn
          |> put_session(:user_did, user.did)
          |> redirect(to: "/oauth/authorize?#{URI.encode_query(query_params)}")
        else
          conn
          |> put_flash(:error, "Invalid session. Please try again.")
          |> redirect(to: "/oauth/login")
        end

      {:error, :invalid_credentials} ->
        conn
        |> put_flash(:error, "Invalid handle or password")
        |> redirect(to: "/oauth/login")
    end
  end

  @doc """
  POST /oauth/authorize/consent

  User grants or denies consent
  """
  def consent(conn, %{"approve" => "true"}) do
    oauth_request = get_session(conn, :oauth_request)
    user_did = get_session(conn, :user_did)

    if oauth_request && user_did do
      # Generate authorization code
      {:ok, auth_code} =
        OAuth.create_authorization_code(
          user_did,
          oauth_request.client_id,
          oauth_request.redirect_uri,
          oauth_request.code_challenge,
          oauth_request.scope
        )

      # Redirect back to client with code
      redirect_params = %{
        code: auth_code,
        state: oauth_request.state,
        iss: AetherPDSServerWeb.Endpoint.url()
      }

      redirect_url = "#{oauth_request.redirect_uri}?#{URI.encode_query(redirect_params)}"

      conn
      |> delete_session(:oauth_request)
      |> redirect(external: redirect_url)
    else
      conn
      |> put_status(:bad_request)
      |> json(%{error: "invalid_request", error_description: "Invalid session"})
    end
  end

  def consent(conn, %{"approve" => "false"}) do
    oauth_request = get_session(conn, :oauth_request)

    if oauth_request do
      redirect_params = %{
        error: "access_denied",
        error_description: "User denied authorization",
        state: oauth_request.state
      }

      redirect_url = "#{oauth_request.redirect_uri}?#{URI.encode_query(redirect_params)}"

      conn
      |> delete_session(:oauth_request)
      |> redirect(external: redirect_url)
    else
      conn
      |> put_status(:bad_request)
      |> json(%{error: "invalid_request"})
    end
  end

  # ============================================================================
  # Token Endpoint
  # ============================================================================

  @doc """
  POST /oauth/token

  Token endpoint - exchanges authorization code for access token
  """
  def token(conn, params) do
    dpop_proof = get_req_header(conn, "dpop") |> List.first()

    case params["grant_type"] do
      "authorization_code" ->
        handle_authorization_code_grant(conn, params, dpop_proof)

      "refresh_token" ->
        handle_refresh_token_grant(conn, params, dpop_proof)

      _ ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          error: "unsupported_grant_type",
          error_description: "Only authorization_code and refresh_token grants are supported"
        })
    end
  end

  defp handle_authorization_code_grant(conn, params, dpop_proof) do
    with {:ok, validated_params} <- validate_token_params(params),
         {:ok, dpop_key} <- OAuth.verify_dpop_proof(dpop_proof, "POST", token_endpoint_url(conn)),
         {:ok, auth_code_data} <- OAuth.validate_authorization_code(validated_params.code),
         :ok <- OAuth.verify_pkce(validated_params.code_verifier, auth_code_data.code_challenge),
         :ok <-
           OAuth.validate_client_match(
             validated_params.client_id,
             validated_params.redirect_uri,
             auth_code_data
           ) do
      # Generate tokens
      {:ok, access_token} =
        OAuth.create_access_token(
          auth_code_data.did,
          auth_code_data.scope,
          dpop_key
        )

      {:ok, refresh_token} =
        OAuth.create_refresh_token(
          auth_code_data.did,
          validated_params.client_id
        )

      # Mark auth code as used
      OAuth.consume_authorization_code(validated_params.code)

      response = %{
        access_token: access_token,
        token_type: "DPoP",
        expires_in: 3600,
        refresh_token: refresh_token,
        scope: auth_code_data.scope,
        sub: auth_code_data.did
      }

      json(conn, response)
    else
      {:error, :missing_dpop_proof} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid_dpop_proof", error_description: "DPoP proof is required"})

      {:error, :invalid_dpop_proof} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid_dpop_proof", error_description: "Invalid DPoP proof"})

      {:error, :invalid_grant} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          error: "invalid_grant",
          error_description: "Authorization code is invalid or expired"
        })

      {:error, :invalid_client} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid_client", error_description: "Client validation failed"})

      {:error, reason} ->
        Logger.error("Token exchange failed: #{inspect(reason)}")

        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid_request", error_description: "Token request failed"})
    end
  end

  defp handle_refresh_token_grant(conn, params, dpop_proof) do
    with {:ok, validated_params} <- validate_refresh_token_params(params),
         {:ok, dpop_key} <- OAuth.verify_dpop_proof(dpop_proof, "POST", token_endpoint_url(conn)),
         {:ok, refresh_token_data} <-
           OAuth.validate_refresh_token(
             validated_params.refresh_token,
             validated_params.client_id
           ) do
      # Generate new access token
      {:ok, access_token} =
        OAuth.create_access_token(
          refresh_token_data.did,
          validated_params.scope || "atproto",
          dpop_key
        )

      response = %{
        access_token: access_token,
        token_type: "DPoP",
        expires_in: 3600,
        scope: validated_params.scope || "atproto",
        sub: refresh_token_data.did
      }

      json(conn, response)
    else
      {:error, :missing_dpop_proof} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid_dpop_proof", error_description: "DPoP proof is required"})

      {:error, :invalid_token} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          error: "invalid_grant",
          error_description: "Refresh token is invalid or expired"
        })

      {:error, reason} ->
        Logger.error("Refresh token failed: #{inspect(reason)}")

        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid_request", error_description: "Token refresh failed"})
    end
  end

  @doc """
  POST /oauth/revoke

  Token revocation endpoint (RFC 7009)
  """
  def revoke(conn, %{"token" => token, "token_type_hint" => token_type_hint}) do
    case token_type_hint do
      "access_token" ->
        OAuth.revoke_access_token(token)

      "refresh_token" ->
        OAuth.revoke_refresh_token(token)

      _ ->
        # Try both if hint not provided
        OAuth.revoke_access_token(token)
        OAuth.revoke_refresh_token(token)
    end

    # Always return 200 OK per RFC 7009
    conn
    |> put_status(:ok)
    |> json(%{})
  end

  def revoke(conn, %{"token" => token}) do
    # No hint provided, try both
    OAuth.revoke_access_token(token)
    OAuth.revoke_refresh_token(token)

    conn
    |> put_status(:ok)
    |> json(%{})
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp validate_authorization_params(params) do
    required = [
      "response_type",
      "client_id",
      "redirect_uri",
      "state",
      "code_challenge",
      "code_challenge_method",
      "scope"
    ]

    if Enum.all?(required, &Map.has_key?(params, &1)) do
      if params["response_type"] == "code" do
        {:ok,
         %{
           response_type: params["response_type"],
           client_id: params["client_id"],
           redirect_uri: params["redirect_uri"],
           state: params["state"],
           code_challenge: params["code_challenge"],
           code_challenge_method: params["code_challenge_method"],
           scope: params["scope"]
         }}
      else
        {:error, :invalid_request}
      end
    else
      {:error, :invalid_request}
    end
  end

  defp validate_token_params(params) do
    required = ["grant_type", "code", "client_id", "redirect_uri", "code_verifier"]

    if Enum.all?(required, &Map.has_key?(params, &1)) do
      {:ok,
       %{
         grant_type: params["grant_type"],
         code: params["code"],
         client_id: params["client_id"],
         redirect_uri: params["redirect_uri"],
         code_verifier: params["code_verifier"]
       }}
    else
      {:error, :invalid_request}
    end
  end

  defp validate_refresh_token_params(params) do
    required = ["grant_type", "refresh_token", "client_id"]

    if Enum.all?(required, &Map.has_key?(params, &1)) do
      {:ok,
       %{
         grant_type: params["grant_type"],
         refresh_token: params["refresh_token"],
         client_id: params["client_id"],
         scope: params["scope"]
       }}
    else
      {:error, :invalid_request}
    end
  end

  defp validate_pkce(code_challenge, "S256") when is_binary(code_challenge) do
    if String.length(code_challenge) >= 43 do
      :ok
    else
      {:error, :invalid_request}
    end
  end

  defp validate_pkce(_, _), do: {:error, :invalid_request}

  defp token_endpoint_url(conn) do
    AetherPDSServerWeb.Endpoint.url() <> conn.request_path
  end

  defp render_consent_page(conn, user, client, oauth_request) do
    # Render HTML consent page
    conn
    |> put_view(AetherPDSServerWeb.OAuthHTML)
    |> put_layout(false)
    |> render(:consent,
      user: user,
      client: client,
      scope: oauth_request.scope
    )
  end
end
