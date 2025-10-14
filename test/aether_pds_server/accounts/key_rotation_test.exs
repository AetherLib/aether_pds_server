defmodule AetherPDSServer.Accounts.KeyRotationTest do
  use AetherPDSServer.DataCase, async: true

  alias AetherPDSServer.Accounts

  describe "rotate_signing_key/2" do
    setup do
      # Create an account with a signing key
      {:ok, account} =
        Accounts.create_account(%{
          handle: "rotatetest.test",
          email: "rotate@example.com",
          password: "password123"
        })

      {:ok, account: account}
    end

    test "rotates the active key successfully", %{account: account} do
      # Get the original active key
      original_key = Accounts.get_active_signing_key(account.id)
      assert original_key.status == "active"

      # Rotate the key
      assert {:ok, %{old_key: old_key, new_key: new_key}} =
               Accounts.rotate_signing_key(account, "k256")

      # Old key should be marked as rotated
      assert old_key.id == original_key.id
      assert old_key.status == "rotated"
      assert old_key.rotated_at != nil

      # New key should be active
      assert new_key.status == "active"
      assert new_key.id != original_key.id
      assert new_key.public_key_multibase != original_key.public_key_multibase
    end

    test "can rotate by DID", %{account: account} do
      assert {:ok, %{old_key: _old_key, new_key: new_key}} =
               Accounts.rotate_signing_key(account.did, "k256")

      assert new_key.status == "active"
    end

    test "returns error for non-existent DID" do
      assert {:error, :account_not_found} =
               Accounts.rotate_signing_key("did:plc:nonexistent", "k256")
    end

    test "only one key is active after rotation", %{account: account} do
      # Rotate the key
      {:ok, _result} = Accounts.rotate_signing_key(account, "k256")

      # Check that only one key is active
      keys = Accounts.list_signing_keys(account.id)
      active_keys = Enum.filter(keys, fn key -> key.status == "active" end)

      assert length(active_keys) == 1
      assert length(keys) == 2
    end

    test "can rotate multiple times", %{account: account} do
      # First rotation
      {:ok, %{new_key: first_new_key}} = Accounts.rotate_signing_key(account, "k256")

      # Second rotation
      {:ok, %{old_key: second_old_key, new_key: second_new_key}} =
        Accounts.rotate_signing_key(account, "k256")

      # Second rotation's old key should be the first rotation's new key
      assert second_old_key.id == first_new_key.id
      assert second_old_key.status == "rotated"

      # Should now have 3 keys total: 2 rotated + 1 active
      keys = Accounts.list_signing_keys(account.id)
      assert length(keys) == 3

      active_keys = Enum.filter(keys, fn key -> key.status == "active" end)
      rotated_keys = Enum.filter(keys, fn key -> key.status == "rotated" end)

      assert length(active_keys) == 1
      assert length(rotated_keys) == 2
      assert hd(active_keys).id == second_new_key.id
    end
  end

  describe "revoke_signing_key/1" do
    setup do
      # Create an account and rotate its key to get a rotated key
      {:ok, account} =
        Accounts.create_account(%{
          handle: "revoketest.test",
          email: "revoke@example.com",
          password: "password123"
        })

      {:ok, %{old_key: rotated_key, new_key: _active_key}} =
        Accounts.rotate_signing_key(account, "k256")

      {:ok, account: account, rotated_key: rotated_key}
    end

    test "revokes a rotated key successfully", %{rotated_key: rotated_key} do
      assert {:ok, revoked_key} = Accounts.revoke_signing_key(rotated_key.id)

      assert revoked_key.status == "revoked"
      assert revoked_key.rotated_at != nil
    end

    test "cannot revoke an active key", %{account: account} do
      active_key = Accounts.get_active_signing_key(account.id)

      assert {:error, :cannot_revoke_active_key} = Accounts.revoke_signing_key(active_key.id)
    end

    test "returns error for non-existent key" do
      assert {:error, :key_not_found} = Accounts.revoke_signing_key(99999)
    end
  end

  describe "list_signing_keys/1" do
    setup do
      {:ok, account} =
        Accounts.create_account(%{
          handle: "listtest.test",
          email: "list@example.com",
          password: "password123"
        })

      # Rotate the key once
      {:ok, %{old_key: old_key, new_key: _new_key}} =
        Accounts.rotate_signing_key(account, "k256")

      # Revoke the old key
      {:ok, _revoked_key} = Accounts.revoke_signing_key(old_key.id)

      {:ok, account: account}
    end

    test "lists all keys in descending order", %{account: account} do
      keys = Accounts.list_signing_keys(account.id)

      # Should have 2 keys: 1 active + 1 revoked
      assert length(keys) == 2

      # Keys should be ordered by inserted_at descending
      # So the most recent (active) key should be first
      [first_key, second_key] = keys

      assert first_key.status == "active"
      assert second_key.status == "revoked"
    end
  end

  describe "get_active_signing_key_by_did/1" do
    test "returns the active signing key for a DID" do
      {:ok, account} =
        Accounts.create_account(%{
          handle: "getactivetest.test",
          email: "getactive@example.com",
          password: "password123"
        })

      key = Accounts.get_active_signing_key_by_did(account.did)

      assert key != nil
      assert key.status == "active"
      assert key.account_id == account.id
    end

    test "returns nil for non-existent DID" do
      assert Accounts.get_active_signing_key_by_did("did:plc:nonexistent") == nil
    end
  end
end
