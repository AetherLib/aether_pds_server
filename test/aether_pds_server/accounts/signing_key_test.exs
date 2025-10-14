defmodule AetherPDSServer.Accounts.SigningKeyTest do
  use AetherPDSServer.DataCase, async: true

  alias AetherPDSServer.Accounts.{Account, SigningKey}
  alias AetherPDSServer.Repo

  describe "changeset/2" do
    setup do
      # Create a test account
      account =
        %Account{}
        |> Account.changeset(%{
          did: "did:plc:test123",
          handle: "test.example.com",
          email: "test@example.com",
          password_hash: "hash123"
        })
        |> Repo.insert!()

      {:ok, account: account}
    end

    test "valid changeset with all required fields", %{account: account} do
      attrs = %{
        account_id: account.id,
        public_key_multibase: "zQ3shokFTS3brHcDQrn82RUDfCZESWL1ZdCEJwekUDPQiYBme",
        private_key_encrypted: "encrypted_key_base64==",
        key_type: "k256",
        status: "active"
      }

      changeset = SigningKey.changeset(%SigningKey{}, attrs)
      assert changeset.valid?
    end

    test "requires all mandatory fields", %{account: _account} do
      changeset = SigningKey.changeset(%SigningKey{}, %{})
      refute changeset.valid?
      assert %{account_id: _, public_key_multibase: _, private_key_encrypted: _} = errors_on(changeset)
    end

    test "validates key_type inclusion", %{account: account} do
      attrs = %{
        account_id: account.id,
        public_key_multibase: "zQ3shokFTS3brHcDQrn82RUDfCZESWL1ZdCEJwekUDPQiYBme",
        private_key_encrypted: "encrypted_key_base64==",
        key_type: "invalid_type",
        status: "active"
      }

      changeset = SigningKey.changeset(%SigningKey{}, attrs)
      refute changeset.valid?
      assert %{key_type: ["is invalid"]} = errors_on(changeset)
    end

    test "validates status inclusion", %{account: account} do
      attrs = %{
        account_id: account.id,
        public_key_multibase: "zQ3shokFTS3brHcDQrn82RUDfCZESWL1ZdCEJwekUDPQiYBme",
        private_key_encrypted: "encrypted_key_base64==",
        key_type: "k256",
        status: "invalid_status"
      }

      changeset = SigningKey.changeset(%SigningKey{}, attrs)
      refute changeset.valid?
      assert %{status: ["is invalid"]} = errors_on(changeset)
    end

    test "validates multibase format (must start with 'z')", %{account: account} do
      attrs = %{
        account_id: account.id,
        public_key_multibase: "invalid_no_z_prefix",
        private_key_encrypted: "encrypted_key_base64==",
        key_type: "k256",
        status: "active"
      }

      changeset = SigningKey.changeset(%SigningKey{}, attrs)
      refute changeset.valid?
      assert %{public_key_multibase: [_]} = errors_on(changeset)
    end

    test "validates multibase minimum length", %{account: account} do
      attrs = %{
        account_id: account.id,
        public_key_multibase: "z123",
        private_key_encrypted: "encrypted_key_base64==",
        key_type: "k256",
        status: "active"
      }

      changeset = SigningKey.changeset(%SigningKey{}, attrs)
      refute changeset.valid?
    end

    test "only one active key per account constraint", %{account: account} do
      # Create first active key
      %SigningKey{}
      |> SigningKey.changeset(%{
        account_id: account.id,
        public_key_multibase: "zQ3shokFTS3brHcDQrn82RUDfCZESWL1ZdCEJwekUDPQiYBme",
        private_key_encrypted: "encrypted_key_base64==",
        key_type: "k256",
        status: "active"
      })
      |> Repo.insert!()

      # Try to create second active key
      changeset =
        %SigningKey{}
        |> SigningKey.changeset(%{
          account_id: account.id,
          public_key_multibase: "zQ3shokFTS3brHcDQrn82RUDfCZESWL1ZdCEJwekUDPQiYBmf",
          private_key_encrypted: "encrypted_key_base64_2==",
          key_type: "k256",
          status: "active"
        })

      assert {:error, changeset} = Repo.insert(changeset)
      assert %{account_id: ["account already has an active signing key"]} = errors_on(changeset)
    end

    test "can have multiple non-active keys", %{account: account} do
      # Create first rotated key
      %SigningKey{}
      |> SigningKey.changeset(%{
        account_id: account.id,
        public_key_multibase: "zQ3shokFTS3brHcDQrn82RUDfCZESWL1ZdCEJwekUDPQiYBme",
        private_key_encrypted: "encrypted_key_base64==",
        key_type: "k256",
        status: "rotated",
        rotated_at: DateTime.utc_now()
      })
      |> Repo.insert!()

      # Create second rotated key - should succeed
      assert {:ok, _} =
               %SigningKey{}
               |> SigningKey.changeset(%{
                 account_id: account.id,
                 public_key_multibase: "zQ3shokFTS3brHcDQrn82RUDfCZESWL1ZdCEJwekUDPQiYBmf",
                 private_key_encrypted: "encrypted_key_base64_2==",
                 key_type: "k256",
                 status: "rotated",
                 rotated_at: DateTime.utc_now()
               })
               |> Repo.insert()
    end
  end

  describe "rotation_changeset/2" do
    setup do
      account =
        %Account{}
        |> Account.changeset(%{
          did: "did:plc:test123",
          handle: "test.example.com",
          email: "test@example.com",
          password_hash: "hash123"
        })
        |> Repo.insert!()

      signing_key =
        %SigningKey{}
        |> SigningKey.changeset(%{
          account_id: account.id,
          public_key_multibase: "zQ3shokFTS3brHcDQrn82RUDfCZESWL1ZdCEJwekUDPQiYBme",
          private_key_encrypted: "encrypted_key_base64==",
          key_type: "k256",
          status: "active"
        })
        |> Repo.insert!()

      {:ok, account: account, signing_key: signing_key}
    end

    test "can rotate a key", %{signing_key: signing_key} do
      attrs = %{
        status: "rotated",
        rotated_at: DateTime.utc_now()
      }

      changeset = SigningKey.rotation_changeset(signing_key, attrs)
      assert changeset.valid?
    end

    test "requires rotated_at", %{signing_key: _signing_key} do
      # When no attrs provided, only rotated_at is missing (status has default "active")
      bare_key = %SigningKey{}
      attrs = %{status: "rotated"}
      changeset = SigningKey.rotation_changeset(bare_key, attrs)
      refute changeset.valid?
      assert %{rotated_at: _} = errors_on(changeset)
    end

    test "accepts only rotated or revoked status", %{signing_key: signing_key} do
      # Test that only "rotated" and "revoked" are accepted
      attrs_rotated = %{status: "rotated", rotated_at: DateTime.utc_now()}
      changeset_rotated = SigningKey.rotation_changeset(signing_key, attrs_rotated)
      assert changeset_rotated.valid?

      attrs_revoked = %{status: "revoked", rotated_at: DateTime.utc_now()}
      changeset_revoked = SigningKey.rotation_changeset(signing_key, attrs_revoked)
      assert changeset_revoked.valid?

      # Invalid status
      attrs_invalid = %{status: "invalid_status", rotated_at: DateTime.utc_now()}
      changeset_invalid = SigningKey.rotation_changeset(signing_key, attrs_invalid)
      refute changeset_invalid.valid?
      assert %{status: _} = errors_on(changeset_invalid)
    end
  end

  describe "associations" do
    test "belongs to account" do
      account =
        %Account{}
        |> Account.changeset(%{
          did: "did:plc:test123",
          handle: "test.example.com",
          email: "test@example.com",
          password_hash: "hash123"
        })
        |> Repo.insert!()

      signing_key =
        %SigningKey{}
        |> SigningKey.changeset(%{
          account_id: account.id,
          public_key_multibase: "zQ3shokFTS3brHcDQrn82RUDfCZESWL1ZdCEJwekUDPQiYBme",
          private_key_encrypted: "encrypted_key_base64==",
          key_type: "k256",
          status: "active"
        })
        |> Repo.insert!()

      loaded_key = Repo.preload(signing_key, :account)
      assert loaded_key.account.id == account.id
    end
  end
end
