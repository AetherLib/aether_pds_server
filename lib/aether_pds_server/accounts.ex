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
  Create a new account, repository, and default profile.
  """
  def create_account(attrs) do
    # Generate a DID for the new account
    did = generate_did(attrs.handle)

    account_attrs =
      attrs
      |> Map.put(:did, did)
      |> Map.put(:password_hash, hash_password(attrs.password))
      |> Map.delete(:password)

    # Create account, repository, and profile in a transaction
    Repo.transaction(fn ->
      with {:ok, account} <-
             %Account{}
             |> Account.changeset(account_attrs)
             |> Repo.insert(),
           {:ok, _repository} <- create_repository_for_account(account),
           {:ok, _profile} <- create_default_profile(account) do
        account
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp create_default_profile(account) do
    profile_record = %{
      "$type" => "app.bsky.actor.profile",
      "displayName" => account.handle,
      "description" => "",
      "createdAt" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    # Generate CID for profile
    profile_cid = generate_cid(profile_record)

    record_attrs = %{
      repository_did: account.did,
      collection: "app.bsky.actor.profile",
      rkey: "self",
      cid: profile_cid,
      value: profile_record
    }

    # Create the profile record (already in transaction)
    Repositories.create_record(record_attrs)
  end

  defp generate_cid(data) do
    hash = :crypto.hash(:sha256, Jason.encode!(data))
    encoded = Base.encode32(hash, case: :lower, padding: false)
    "bafyrei" <> String.slice(encoded, 0..50)
  end

  @doc """
  Create a repository for an account with initial commit.
  """
  def create_repository_for_account(account) do
    alias AetherPDSServer.Repositories
    alias Aether.ATProto.{MST, Commit, CID}

    # Create empty MST
    mst = %MST{}

    # Generate MST root CID (empty tree)
    mst_root_cid = generate_mst_cid(mst)

    # Create initial commit
    rev = Aether.ATProto.TID.new()
    commit = Commit.create(account.did, mst_root_cid, rev: rev)
    commit_cid = Commit.cid(commit)
    commit_cid_string = CID.cid_to_string(commit_cid)

    # Create repository with initial commit
    repository_attrs = %{
      did: account.did,
      head_cid: commit_cid_string
    }

    with {:ok, repository} <- Repositories.create_repository(repository_attrs),
         {:ok, _commit} <-
           Repositories.create_commit(%{
             repository_did: account.did,
             cid: commit_cid_string,
             rev: rev,
             prev: nil,
             data: %{
               version: 3,
               did: account.did,
               rev: rev,
               data: CID.cid_to_string(mst_root_cid)
             }
           }) do
      {:ok, repository}
    end
  end

  defp generate_mst_cid(%Aether.ATProto.MST{}) do
    alias Aether.ATProto.CID

    # Generate CID for empty MST
    # In production, this would be the actual CBOR-encoded MST data
    hash = :crypto.hash(:sha256, "empty_mst")
    hash_encoded = Base.encode32(hash, case: :lower, padding: false)
    cid_string = "bafyrei" <> String.slice(hash_encoded, 0..50)

    case CID.parse_cid(cid_string) do
      {:ok, cid} -> cid
      {:error, _} -> CID.new(1, "dag-cbor", cid_string)
    end
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
    # Generate proper JWT instead of random token
    case AetherPDSServer.Token.generate_access_token(did) do
      {:ok, token, _claims} -> {:ok, token}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Create a refresh token for an account.
  """

  # def create_refresh_token(did) do
  #   # For simple auth, use "internal" as client_id
  #   OAuth.create_refresh_token(did, "internal")
  # end

  def create_refresh_token(did) do
    # Generate proper JWT instead of random token
    case AetherPDSServer.Token.generate_refresh_token(did) do
      {:ok, token, _claims} -> {:ok, token}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Refresh a session using a refresh token.
  """

  # def refresh_session(refresh_token) do
  #   case OAuth.validate_refresh_token(refresh_token, "internal") do
  #     {:ok, refresh_token_data} ->
  #       account = get_account_by_did!(refresh_token_data.did)
  #       {:ok, new_access_token} = create_access_token(account.did)
  #       {:ok, new_refresh_token} = create_refresh_token(account.did)

  #       # Revoke old refresh token
  #       OAuth.revoke_refresh_token(refresh_token)

  #       {:ok, account, new_access_token, new_refresh_token}

  #     {:error, _} ->
  #       {:error, :invalid_token}
  #   end
  # end

  def refresh_session(refresh_token) do
    # Verify the JWT
    case AetherPDSServer.Token.verify_token(refresh_token) do
      {:ok, %{"sub" => did}} ->
        account = get_account_by_did!(did)
        {:ok, new_access_token} = create_access_token(account.did)
        {:ok, new_refresh_token} = create_refresh_token(account.did)

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
