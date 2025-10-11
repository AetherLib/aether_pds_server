# lib/aether_pds_server/accounts.ex
defmodule AetherPDSServer.Accounts do
  @moduledoc """
  The Accounts context for managing users, authentication, and sessions.
  """

  alias AetherPDSServer.Repo
  alias AetherPDSServer.Repositories
  alias AetherPDSServer.Accounts.Account
  alias AetherPDSServer.Accounts.AppPassword
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
    alias Aether.ATProto.CID
    CID.from_map(data)
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

  @doc """
  List all accounts.
  """
  def list_accounts do
    import Ecto.Query

    Repo.all(from a in Account, order_by: [asc: a.handle])
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
        # Check account status
        cond do
          account.status == "deleted" ->
            {:error, :account_deleted}

          account.status == "deactivated" ->
            {:error, :account_deactivated}

          verify_password(password, account.password_hash) ->
            {:ok, account}

          true ->
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
    # Use did:web method which resolves via HTTPS at the handle's domain
    # This avoids needing to register with the PLC directory
    # Format: did:web:handle (e.g., did:web:alice.aetherlib.org)
    "did:web:#{handle}"
  end

  # ============================================================================
  # App Password Management
  # ============================================================================

  @doc """
  Create an app password for an account.

  Returns the created app password struct with the plaintext password.
  The plaintext password is only returned once at creation time.
  """
  def create_app_password(account_id, attrs) when is_integer(account_id) do
    # Generate a random app password if not provided
    password = Map.get(attrs, :password) || generate_app_password()

    attrs_with_password =
      attrs
      |> Map.put(:account_id, account_id)
      |> Map.put(:password, password)

    result =
      %AppPassword{}
      |> AppPassword.create_changeset(attrs_with_password)
      |> Repo.insert()

    case result do
      {:ok, app_password} ->
        # Return app password with plaintext password for one-time display
        {:ok, %{app_password | password: password}}

      error ->
        error
    end
  end

  @doc """
  List all app passwords for an account.

  Does not include password hashes or plaintext passwords.
  """
  def list_app_passwords(account_id) when is_integer(account_id) do
    import Ecto.Query

    Repo.all(
      from ap in AppPassword,
        where: ap.account_id == ^account_id,
        order_by: [desc: ap.created_at],
        select: %{
          name: ap.name,
          created_at: ap.created_at,
          privileged: ap.privileged
        }
    )
  end

  @doc """
  Revoke (delete) an app password by name for an account.
  """
  def revoke_app_password(account_id, name) when is_integer(account_id) and is_binary(name) do
    import Ecto.Query

    case Repo.get_by(AppPassword, account_id: account_id, name: name) do
      nil ->
        {:error, :not_found}

      app_password ->
        Repo.delete(app_password)
    end
  end

  @doc """
  Authenticate a user by handle/email and app password.

  Returns {:ok, account} if authentication succeeds.
  """
  def authenticate_with_app_password(identifier, password) do
    import Ecto.Query

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
        # Check if password matches any app password
        app_password =
          Repo.one(
            from ap in AppPassword,
              where: ap.account_id == ^account.id
          )

        case app_password do
          nil ->
            {:error, :invalid_credentials}

          app_password ->
            if verify_password(password, app_password.password_hash) do
              {:ok, account}
            else
              {:error, :invalid_credentials}
            end
        end
    end
  end

  @doc """
  Generate a random app password.

  Format: xxxx-xxxx-xxxx-xxxx (4 groups of 4 alphanumeric characters)
  """
  defp generate_app_password do
    chars = "abcdefghijklmnopqrstuvwxyz0123456789"

    1..4
    |> Enum.map(fn _ ->
      1..4
      |> Enum.map(fn _ ->
        String.at(chars, :rand.uniform(String.length(chars)) - 1)
      end)
      |> Enum.join()
    end)
    |> Enum.join("-")
  end

  # ============================================================================
  # Account Lifecycle Management
  # ============================================================================

  @doc """
  Deactivate an account.

  Deactivated accounts cannot authenticate but can be reactivated.
  """
  def deactivate_account(did) when is_binary(did) do
    case get_account_by_did(did) do
      nil ->
        {:error, :account_not_found}

      account ->
        account
        |> Account.changeset(%{
          status: "deactivated",
          deactivated_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
        })
        |> Repo.update()
    end
  end

  @doc """
  Activate a previously deactivated account.
  """
  def activate_account(did) when is_binary(did) do
    case get_account_by_did(did) do
      nil ->
        {:error, :account_not_found}

      account ->
        if account.status == "deleted" do
          {:error, :account_deleted}
        else
          account
          |> Account.changeset(%{
            status: "active",
            deactivated_at: nil
          })
          |> Repo.update()
        end
    end
  end

  @doc """
  Delete an account permanently.

  This marks the account as deleted but doesn't remove it from the database.
  Deleted accounts cannot be reactivated.
  """
  def delete_account(did, password) when is_binary(did) and is_binary(password) do
    case get_account_by_did(did) do
      nil ->
        {:error, :account_not_found}

      account ->
        # Verify password before deletion
        if verify_password(password, account.password_hash) do
          account
          |> Account.changeset(%{
            status: "deleted",
            deactivated_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
          })
          |> Repo.update()
        else
          {:error, :invalid_password}
        end
    end
  end

  @doc """
  Check if an account is active.
  """
  def account_active?(did) when is_binary(did) do
    case get_account_by_did(did) do
      nil -> false
      account -> account.status == "active"
    end
  end

  @doc """
  Get account status.
  """
  def get_account_status(did) when is_binary(did) do
    case get_account_by_did(did) do
      nil -> {:error, :account_not_found}
      account -> {:ok, account.status}
    end
  end
end
