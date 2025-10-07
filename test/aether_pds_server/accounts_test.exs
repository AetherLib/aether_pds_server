defmodule AetherPDSServer.AccountsTest do
  use AetherPDSServer.DataCase

  alias AetherPDSServer.Accounts
  alias AetherPDSServer.Repositories

  describe "create_account/1" do
    test "creates account with valid attributes" do
      attrs = %{
        handle: "testuser.test",
        email: "test@example.com",
        password: "securepassword123"
      }

      assert {:ok, account} = Accounts.create_account(attrs)
      assert account.handle == "testuser.test"
      assert account.email == "test@example.com"
      assert String.starts_with?(account.did, "did:plc:")
      assert is_binary(account.password_hash)
      refute account.password_hash == "securepassword123"
    end

    test "automatically creates repository on account creation" do
      attrs = %{
        handle: "testuser.test",
        email: "test@example.com",
        password: "securepassword123"
      }

      assert {:ok, account} = Accounts.create_account(attrs)

      # Repository should exist
      assert repository = Repositories.get_repository(account.did)
      assert repository.did == account.did
      assert is_binary(repository.head_cid)
    end

    test "creates initial commit for repository" do
      attrs = %{
        handle: "testuser.test",
        email: "test@example.com",
        password: "securepassword123"
      }

      assert {:ok, account} = Accounts.create_account(attrs)

      # Should have at least one commit
      commits = Repositories.list_commits(account.did)
      assert length(commits) > 0

      commit = List.first(commits)
      assert commit.repository_did == account.did
      assert is_binary(commit.cid)
      assert is_binary(commit.rev)
    end

    test "fails with missing required fields" do
      attrs = %{handle: "testuser.test", password: "test"}

      assert {:error, changeset} = Accounts.create_account(attrs)
      assert %Ecto.Changeset{} = changeset
    end

    test "fails with duplicate handle" do
      attrs = %{
        handle: "testuser.test",
        email: "test@example.com",
        password: "securepassword123"
      }

      assert {:ok, _account} = Accounts.create_account(attrs)

      # Try to create another account with same handle
      attrs2 = %{
        handle: "testuser.test",
        email: "test2@example.com",
        password: "securepassword456"
      }

      assert {:error, _} = Accounts.create_account(attrs2)
    end
  end

  describe "get_account_by_did/1" do
    test "returns account when found" do
      {:ok, account} =
        Accounts.create_account(%{
          handle: "testuser.test",
          email: "test@example.com",
          password: "password123"
        })

      assert found = Accounts.get_account_by_did(account.did)
      assert found.did == account.did
      assert found.handle == "testuser.test"
    end

    test "returns nil when not found" do
      assert Accounts.get_account_by_did("did:plc:nonexistent") == nil
    end
  end

  describe "get_account_by_handle/1" do
    test "returns account when found" do
      {:ok, account} =
        Accounts.create_account(%{
          handle: "testuser.test",
          email: "test@example.com",
          password: "password123"
        })

      assert found = Accounts.get_account_by_handle("testuser.test")
      assert found.handle == "testuser.test"
      assert found.did == account.did
    end

    test "returns nil when not found" do
      assert Accounts.get_account_by_handle("nonexistent.test") == nil
    end
  end

  describe "get_account_by_email/1" do
    test "returns account when found" do
      {:ok, account} =
        Accounts.create_account(%{
          handle: "testuser.test",
          email: "test@example.com",
          password: "password123"
        })

      assert found = Accounts.get_account_by_email("test@example.com")
      assert found.email == "test@example.com"
      assert found.did == account.did
    end

    test "returns nil when not found" do
      assert Accounts.get_account_by_email("nonexistent@example.com") == nil
    end
  end

  describe "authenticate/2" do
    setup do
      {:ok, account} =
        Accounts.create_account(%{
          handle: "testuser.test",
          email: "test@example.com",
          password: "correctpassword"
        })

      %{account: account}
    end

    test "authenticates with valid handle and password", %{account: account} do
      assert {:ok, authenticated} = Accounts.authenticate("testuser.test", "correctpassword")
      assert authenticated.did == account.did
    end

    test "authenticates with valid email and password", %{account: account} do
      assert {:ok, authenticated} = Accounts.authenticate("test@example.com", "correctpassword")
      assert authenticated.did == account.did
    end

    test "fails with invalid password" do
      assert {:error, :invalid_credentials} =
               Accounts.authenticate("testuser.test", "wrongpassword")
    end

    test "fails with non-existent user" do
      assert {:error, :invalid_credentials} =
               Accounts.authenticate("nonexistent.test", "password")
    end
  end

  describe "create_access_token/1" do
    test "creates access token for account" do
      {:ok, account} =
        Accounts.create_account(%{
          handle: "testuser.test",
          email: "test@example.com",
          password: "password123"
        })

      assert {:ok, token} = Accounts.create_access_token(account.did)
      assert is_binary(token)
      assert String.length(token) > 20
    end
  end

  describe "create_refresh_token/1" do
    test "creates refresh token for account" do
      {:ok, account} =
        Accounts.create_account(%{
          handle: "testuser.test",
          email: "test@example.com",
          password: "password123"
        })

      assert {:ok, token} = Accounts.create_refresh_token(account.did)
      assert is_binary(token)
      assert String.length(token) > 20
    end
  end

  describe "refresh_session/1" do
    test "refreshes session with valid token" do
      {:ok, account} =
        Accounts.create_account(%{
          handle: "testuser.test",
          email: "test@example.com",
          password: "password123"
        })

      {:ok, refresh_token} = Accounts.create_refresh_token(account.did)

      assert {:ok, found_account, new_access, new_refresh} =
               Accounts.refresh_session(refresh_token)

      assert found_account.did == account.did
      assert is_binary(new_access)
      assert is_binary(new_refresh)
      assert new_access != new_refresh
    end

    test "fails with invalid token" do
      assert {:error, :invalid_token} = Accounts.refresh_session("invalid_token")
    end
  end
end
