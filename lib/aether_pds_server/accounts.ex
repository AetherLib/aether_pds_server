# lib/aether_pds_server/accounts.ex
defmodule AetherPDSServer.Accounts do
  @moduledoc """
  The Accounts context for managing users, authentication, and sessions.
  """

  alias AetherPDSServer.Repo
  alias AetherPDSServer.Accounts.Account
  alias AetherPDSServer.OAuth

  # ============================================================================
  # Account Management
  # ============================================================================

  @doc """
  Create a new account.
  """
  def create_account(attrs) do
    # Generate a DID for the new account
    did = generate_did(attrs.handle)

    account_attrs =
      attrs
      |> Map.put(:did, did)
      |> Map.put(:password_hash, hash_password(attrs.password))
      |> Map.delete(:password)

    %Account{}
    |> Account.changeset(account_attrs)
    |> Repo.insert()
  end

  @doc """
  Get an account by DID.
  """
  def get_account_by_did(did) do
    Repo.get_by(Account, did: did)
  end

  @doc """
  Get an account by DID, raises if not found.
  """
  def get_account_by_did!(did) do
    Repo.get_by!(Account, did: did)
  end

  @doc """
  Get an account by handle.
  """
  def get_account_by_handle(handle) do
    Repo.get_by(Account, handle: handle)
  end

  @doc """
  Get an account by email.
  """
  def get_account_by_email(email) do
    Repo.get_by(Account, email: email)
  end

  # ============================================================================
  # Authentication
  # ============================================================================

  @doc """
  Authenticate a user by handle/email and password.
  """
  def authenticate(identifier, password) do
    # Try to find by handle or email
    account =
      cond do
        String.contains?(identifier, "@") ->
          get_account_by_email(identifier)

        true ->
          get_account_by_handle(identifier)
      end

    case account do
      nil ->
        # Run hash to prevent timing attacks
        Argon2.no_user_verify()
        {:error, :invalid_credentials}

      account ->
        if verify_password(password, account.password_hash) do
          {:ok, account}
        else
          {:error, :invalid_credentials}
        end
    end
  end

  @doc """
  Authenticate user (alias for OAuth controller).
  """
  def authenticate_user(handle, password) do
    authenticate(handle, password)
  end

  @doc """
  Get user by DID (alias for OAuth controller).
  """
  def get_user_by_did!(did) do
    get_account_by_did!(did)
  end

  # ============================================================================
  # Token Management (Delegates to OAuth)
  # ============================================================================

  @doc """
  Create an access token for an account.

  Note: This requires a DPoP key. For simple session-based auth without DPoP,
  use the OAuth module directly or implement session tokens separately.
  """
  def create_access_token(did) do
    # Generate a dummy DPoP key for now
    # In production, this would come from the OAuth flow
    dummy_dpop_key = %{
      "kty" => "EC",
      "crv" => "P-256",
      "x" => Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false),
      "y" => Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    }

    OAuth.create_access_token(did, "atproto", dummy_dpop_key)
  end

  @doc """
  Create a refresh token for an account.
  """
  def create_refresh_token(did) do
    # For simple auth, use "internal" as client_id
    OAuth.create_refresh_token(did, "internal")
  end

  @doc """
  Refresh a session using a refresh token.
  """
  def refresh_session(refresh_token) do
    case OAuth.validate_refresh_token(refresh_token, "internal") do
      {:ok, refresh_token_data} ->
        account = get_account_by_did!(refresh_token_data.did)
        {:ok, new_access_token} = create_access_token(account.did)
        {:ok, new_refresh_token} = create_refresh_token(account.did)

        # Revoke old refresh token
        OAuth.revoke_refresh_token(refresh_token)

        {:ok, account, new_access_token, new_refresh_token}

      {:error, _} ->
        {:error, :invalid_token}
    end
  end

  # ============================================================================
  # Password Hashing
  # ============================================================================

  defp hash_password(password) do
    Argon2.hash_pwd_salt(password)
  end

  defp verify_password(password, hash) do
    Argon2.verify_pass(password, hash)
  end

  # ============================================================================
  # DID Generation
  # ============================================================================

  defp generate_did(handle) do
    # For now, use a simple did:plc format
    # In production, you'd generate a proper PLC DID
    identifier =
      :crypto.hash(:sha256, handle)
      |> Base.encode32(case: :lower, padding: false)
      |> String.slice(0..23)

    "did:plc:#{identifier}"
  end
end
