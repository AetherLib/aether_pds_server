defmodule AetherPDSServer.Repositories.CommitSignerTest do
  use AetherPDSServer.DataCase, async: true

  alias AetherPDSServer.Repositories.CommitSigner
  alias AetherPDSServer.Accounts
  alias Aether.ATProto.{Commit, CID}

  describe "sign_commit/2" do
    setup do
      # Create an account with a signing key
      {:ok, account} =
        Accounts.create_account(%{
          handle: "testuser.test",
          email: "test@example.com",
          password: "password123"
        })

      # Create a test commit
      mst_root_cid = create_test_mst_cid()
      rev = Aether.ATProto.TID.new()
      commit = Commit.create(account.did, mst_root_cid, rev: rev)

      {:ok, account: account, commit: commit}
    end

    test "signs a commit successfully", %{account: account, commit: commit} do
      assert {:ok, signature} = CommitSigner.sign_commit(commit, account.did)
      assert is_binary(signature)
      # Signature should be base64 encoded
      assert {:ok, _decoded} = Base.decode64(signature)
    end

    test "returns error for non-existent account", %{commit: commit} do
      assert {:error, :account_not_found} = CommitSigner.sign_commit(commit, "did:plc:nonexistent")
    end

    test "generates different signatures for different commits", %{account: account} do
      # Create two different commits
      mst_root_cid1 = create_test_mst_cid()
      mst_root_cid2 = create_test_mst_cid()
      rev1 = Aether.ATProto.TID.new()
      rev2 = Aether.ATProto.TID.new()

      commit1 = Commit.create(account.did, mst_root_cid1, rev: rev1)
      commit2 = Commit.create(account.did, mst_root_cid2, rev: rev2)

      assert {:ok, sig1} = CommitSigner.sign_commit(commit1, account.did)
      assert {:ok, sig2} = CommitSigner.sign_commit(commit2, account.did)

      # Signatures should be different
      assert sig1 != sig2
    end
  end

  describe "verify_commit/3" do
    setup do
      # Create an account with a signing key
      {:ok, account} =
        Accounts.create_account(%{
          handle: "verifytest.test",
          email: "verify@example.com",
          password: "password123"
        })

      # Create and sign a test commit
      mst_root_cid = create_test_mst_cid()
      rev = Aether.ATProto.TID.new()
      commit = Commit.create(account.did, mst_root_cid, rev: rev)
      {:ok, signature} = CommitSigner.sign_commit(commit, account.did)

      {:ok, account: account, commit: commit, signature: signature}
    end

    test "verifies a valid signature", %{account: account, commit: commit, signature: signature} do
      assert {:ok, true} = CommitSigner.verify_commit(commit, signature, account.did)
    end

    test "fails for tampered signature", %{account: account, commit: commit, signature: signature} do
      # Tamper with the signature
      tampered = String.replace(signature, "A", "B", global: false)

      # Should either fail to decode or verify as false
      case CommitSigner.verify_commit(commit, tampered, account.did) do
        {:ok, false} -> assert true
        {:error, _} -> assert true
        {:ok, true} -> flunk("Tampered signature should not verify")
      end
    end

    test "fails for wrong commit data", %{account: account, signature: signature} do
      # Create a different commit
      different_mst_cid = create_test_mst_cid()
      different_rev = Aether.ATProto.TID.new()
      different_commit = Commit.create(account.did, different_mst_cid, rev: different_rev)

      # Signature from original commit should not verify for different commit
      assert {:ok, false} = CommitSigner.verify_commit(different_commit, signature, account.did)
    end

    test "returns error for non-existent account", %{commit: commit, signature: signature} do
      assert {:error, :account_not_found} =
               CommitSigner.verify_commit(commit, signature, "did:plc:nonexistent")
    end
  end

  describe "create_signed_commit/3" do
    setup do
      # Create an account with a signing key
      {:ok, account} =
        Accounts.create_account(%{
          handle: "signedtest.test",
          email: "signed@example.com",
          password: "password123"
        })

      {:ok, account: account}
    end

    test "creates and signs a commit", %{account: account} do
      mst_root_cid = create_test_mst_cid()
      rev = Aether.ATProto.TID.new()

      assert {:ok, %{commit: commit, signature: signature}} =
               CommitSigner.create_signed_commit(account.did, mst_root_cid, rev: rev)

      assert %Commit{} = commit
      assert is_binary(signature)

      # Verify the signature is valid
      assert {:ok, true} = CommitSigner.verify_commit(commit, signature, account.did)
    end

    test "handles optional prev parameter", %{account: account} do
      mst_root_cid = create_test_mst_cid()
      rev = Aether.ATProto.TID.new()
      prev_cid = CID.new(1, "dag-cbor", "bafy...")

      assert {:ok, %{commit: commit, signature: _}} =
               CommitSigner.create_signed_commit(account.did, mst_root_cid, rev: rev, prev: prev_cid)

      assert commit.prev == prev_cid
    end
  end

  describe "end-to-end account creation" do
    test "new accounts have signed initial commits" do
      # Create a new account
      {:ok, account} =
        Accounts.create_account(%{
          handle: "newaccount.test",
          email: "new@example.com",
          password: "password123"
        })

      # Check that the account has a repository
      repository = AetherPDSServer.Repositories.get_repository(account.did)
      assert repository

      # Check that there's a commit with a signature
      import Ecto.Query
      commit =
        AetherPDSServer.Repo.one(
          from c in AetherPDSServer.Repositories.Commit,
            where: c.repository_did == ^account.did,
            limit: 1
        )

      assert commit
      assert commit.signature, "Initial commit should have a signature"
      assert is_binary(commit.signature)
    end
  end

  # Helper functions

  defp create_test_mst_cid do
    # Create a simple MST CID for testing
    empty_mst_data =
      CBOR.encode(%{
        layer: 0,
        entries: []
      })

    cid_string = CID.from_data(empty_mst_data, "dag-cbor")

    case CID.parse_cid(cid_string) do
      {:ok, cid} -> cid
      {:error, _} -> CID.new(1, "dag-cbor", cid_string)
    end
  end
end
