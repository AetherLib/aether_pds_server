defmodule AetherPDSServer.OAuth do
  @moduledoc """
  OAuth and DPoP implementation for PDS authorization server.
  """

  import Ecto.Query
  alias AetherPDSServer.Repo
  alias AetherPDSServer.OAuth.{AuthorizationCode, AccessToken, RefreshToken}
  alias Aether.ATProto.Crypto.DPoP

  # ============================================================================
  # Client Validation
  # ============================================================================

  @doc """
  Validate a client_id and redirect_uri combination.

  Returns {:ok, client_info} if valid, {:error, reason} otherwise.
  """
  def validate_client(client_id, redirect_uri) do
    # Parse client_id (could be URL with metadata or loopback)
    cond do
      # Loopback client (for development/localhost apps)
      String.starts_with?(client_id, "http://localhost") or
          String.starts_with?(client_id, "http://127.0.0.1") ->
        {:ok,
         %{
           id: client_id,
           name: "Local Development Client",
           type: :loopback,
           redirect_uri: redirect_uri
         }}

      # Web-based client (must fetch client metadata)
      String.starts_with?(client_id, "http://") or
          String.starts_with?(client_id, "https://") ->
        fetch_client_metadata(client_id, redirect_uri)

      true ->
        {:error, :invalid_client}
    end
  end

  defp fetch_client_metadata(client_id, expected_redirect_uri) do
    # Fetch client metadata from client_id URL
    metadata_url = "#{client_id}/client-metadata.json"

    case Req.get(metadata_url) do
      {:ok, %{status: 200, body: metadata}} ->
        if expected_redirect_uri in metadata["redirect_uris"] do
          {:ok,
           %{
             id: client_id,
             name: metadata["client_name"] || client_id,
             type: :web,
             redirect_uri: expected_redirect_uri,
             metadata: metadata
           }}
        else
          {:error, :invalid_redirect_uri}
        end

      _ ->
        {:error, :invalid_client}
    end
  end

  # ============================================================================
  # Authorization Code
  # ============================================================================

  @doc """
  Create an authorization code for the OAuth flow.
  """
  def create_authorization_code(did, client_id, redirect_uri, code_challenge, scope) do
    code = generate_secure_token(32)
    expires_at = DateTime.add(DateTime.utc_now(), 600, :second)

    attrs = %{
      code: code,
      did: did,
      client_id: client_id,
      redirect_uri: redirect_uri,
      code_challenge: code_challenge,
      scope: scope,
      expires_at: expires_at,
      used: false
    }

    case Repo.insert(AuthorizationCode.changeset(%AuthorizationCode{}, attrs)) do
      {:ok, _auth_code} -> {:ok, code}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Validate an authorization code.

  Returns {:ok, auth_code_data} if valid and not expired/used.
  """
  def validate_authorization_code(code) do
    query =
      from ac in AuthorizationCode,
        where: ac.code == ^code,
        where: ac.used == false,
        where: ac.expires_at > ^DateTime.utc_now()

    case Repo.one(query) do
      nil -> {:error, :invalid_grant}
      auth_code -> {:ok, auth_code}
    end
  end

  @doc """
  Mark an authorization code as used.
  """
  def consume_authorization_code(code) do
    query = from ac in AuthorizationCode, where: ac.code == ^code
    Repo.update_all(query, set: [used: true])
  end

  # ============================================================================
  # PKCE Verification
  # ============================================================================

  @doc """
  Verify PKCE code_verifier matches the stored code_challenge.
  """
  def verify_pkce(code_verifier, code_challenge) do
    computed_challenge =
      :crypto.hash(:sha256, code_verifier)
      |> Base.url_encode64(padding: false)

    if computed_challenge == code_challenge do
      :ok
    else
      {:error, :invalid_grant}
    end
  end

  # ============================================================================
  # DPoP Verification
  # ============================================================================

  @doc """
  Verify a DPoP proof JWT.

  Returns {:ok, dpop_key} if valid, {:error, reason} otherwise.
  """
  def verify_dpop_proof(nil, _method, _url), do: {:error, :missing_dpop_proof}

  def verify_dpop_proof(dpop_jwt, method, url) do
    case DPoP.verify_proof(dpop_jwt, method, url) do
      {:ok, dpop_key} -> {:ok, dpop_key}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Verify DPoP binding - ensure the DPoP key matches the access token's JKT.
  """
  def verify_dpop_binding(dpop_key, expected_jkt) do
    actual_jkt = DPoP.calculate_jkt(dpop_key)

    if actual_jkt == expected_jkt do
      :ok
    else
      {:error, :invalid_dpop_binding}
    end
  end

  # ============================================================================
  # Access Tokens
  # ============================================================================

  @doc """
  Create an access token with DPoP binding.
  """
  def create_access_token(did, scope, dpop_key) do
    token = generate_secure_token(32)
    jkt = DPoP.calculate_jkt(dpop_key)
    expires_at = DateTime.add(DateTime.utc_now(), 3600, :second)

    attrs = %{
      token: token,
      did: did,
      scope: scope,
      jkt: jkt,
      expires_at: expires_at
    }

    case Repo.insert(AccessToken.changeset(%AccessToken{}, attrs)) do
      {:ok, _} -> {:ok, token}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Get a simple access token (without DPoP validation).

  Used for testing and simple authentication flows.
  Returns {:ok, did} if valid, {:error, reason} otherwise.
  """
  def get_simple_access_token(token_string) do
    query =
      from at in AccessToken,
        where: at.token == ^token_string,
        where: at.revoked == false,
        where: at.expires_at > ^DateTime.utc_now()

    case Repo.one(query) do
      nil -> {:error, :invalid_token}
      access_token -> {:ok, access_token.did}
    end
  end

  @doc """
  Validate an access token with DPoP proof.

  Returns {:ok, token_data} if valid, {:error, reason} otherwise.
  """
  def validate_access_token(token_string, dpop_proof, method, url) do
    query =
      from at in AccessToken,
        where: at.token == ^token_string,
        where: at.revoked == false,
        where: at.expires_at > ^DateTime.utc_now()

    case Repo.one(query) do
      nil ->
        {:error, :invalid_token}

      access_token ->
        # Verify DPoP proof matches the token's JKT
        with {:ok, dpop_key} <- verify_dpop_proof(dpop_proof, method, url),
             :ok <- verify_dpop_binding(dpop_key, access_token.jkt),
             :ok <- verify_ath_in_proof(dpop_proof, token_string) do
          {:ok,
           %{
             did: access_token.did,
             scope: access_token.scope,
             token: access_token
           }}
        end
    end
  end

  defp verify_ath_in_proof(dpop_jwt, access_token) do
    # Parse the DPoP JWT to check ath claim
    case String.split(dpop_jwt, ".") do
      [_header_b64, payload_b64, _sig_b64] ->
        with {:ok, payload_json} <- Base.url_decode64(payload_b64, padding: false),
             {:ok, claims} <- Jason.decode(payload_json) do
          expected_ath =
            :crypto.hash(:sha256, access_token)
            |> Base.url_encode64(padding: false)

          case claims["ath"] do
            ^expected_ath -> :ok
            nil -> {:error, :missing_ath}
            _ -> {:error, :invalid_ath}
          end
        else
          _ -> {:error, :invalid_dpop_proof}
        end

      _ ->
        {:error, :invalid_dpop_proof}
    end
  end

  @doc """
  Revoke an access token.
  """
  def revoke_access_token(token_string) do
    query = from at in AccessToken, where: at.token == ^token_string

    case Repo.update_all(query, set: [revoked: true]) do
      {1, _} -> :ok
      {0, _} -> {:error, :not_found}
    end
  end

  # ============================================================================
  # Refresh Tokens
  # ============================================================================

  @doc """
  Create a refresh token.
  """
  def create_refresh_token(did, client_id) do
    token = generate_secure_token(32)
    expires_at = DateTime.add(DateTime.utc_now(), 86400 * 30, :second)

    attrs = %{
      token: token,
      did: did,
      client_id: client_id,
      expires_at: expires_at
    }

    case Repo.insert(RefreshToken.changeset(%RefreshToken{}, attrs)) do
      {:ok, _} -> {:ok, token}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Validate a refresh token.
  """
  def validate_refresh_token(token_string, client_id) do
    query =
      from rt in RefreshToken,
        where: rt.token == ^token_string,
        where: rt.client_id == ^client_id,
        where: rt.revoked == false,
        where: rt.expires_at > ^DateTime.utc_now()

    case Repo.one(query) do
      nil -> {:error, :invalid_token}
      refresh_token -> {:ok, refresh_token}
    end
  end

  @doc """
  Revoke a refresh token.
  """
  def revoke_refresh_token(token_string) do
    query = from rt in RefreshToken, where: rt.token == ^token_string

    case Repo.update_all(query, set: [revoked: true]) do
      {1, _} -> :ok
      {0, _} -> {:error, :not_found}
    end
  end

  # ============================================================================
  # Token Management
  # ============================================================================

  @doc """
  Revoke all tokens for a DID (used during logout).
  """
  def revoke_all_tokens_for_did(did) do
    Repo.transaction(fn ->
      # Revoke all access tokens
      from(at in AccessToken, where: at.did == ^did)
      |> Repo.update_all(set: [revoked: true])

      # Revoke all refresh tokens
      from(rt in RefreshToken, where: rt.did == ^did)
      |> Repo.update_all(set: [revoked: true])
    end)
  end

  @doc """
  Clean up expired tokens (run periodically via a scheduled job).
  """
  def cleanup_expired_tokens do
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      # Delete expired authorization codes
      from(ac in AuthorizationCode, where: ac.expires_at < ^now)
      |> Repo.delete_all()

      # Delete expired access tokens
      from(at in AccessToken, where: at.expires_at < ^now)
      |> Repo.delete_all()

      # Delete expired refresh tokens
      from(rt in RefreshToken, where: rt.expires_at < ^now)
      |> Repo.delete_all()
    end)
  end

  # ============================================================================
  # Client Validation Helpers
  # ============================================================================

  @doc """
  Validate client metadata document (for PAR endpoint).

  For PAR, we only need to validate that the client_id is a valid URL.
  The full metadata fetch will happen during the authorization flow.
  """
  def validate_client_metadata(client_id) when is_binary(client_id) do
    cond do
      String.starts_with?(client_id, "http://localhost") or
          String.starts_with?(client_id, "http://127.0.0.1") ->
        {:ok, %{id: client_id, type: :loopback}}

      String.starts_with?(client_id, "http://") or String.starts_with?(client_id, "https://") ->
        {:ok, %{id: client_id, type: :web}}

      true ->
        {:error, :invalid_client}
    end
  end

  def validate_client_metadata(_), do: {:error, :invalid_client}

  @doc """
  Validate that client_id and redirect_uri match the authorization code.
  """
  def validate_client_match(client_id, redirect_uri, auth_code_data) do
    if auth_code_data.client_id == client_id and
         auth_code_data.redirect_uri == redirect_uri do
      :ok
    else
      {:error, :invalid_client}
    end
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp generate_secure_token(length) do
    :crypto.strong_rand_bytes(length)
    |> Base.url_encode64(padding: false)
  end
end
