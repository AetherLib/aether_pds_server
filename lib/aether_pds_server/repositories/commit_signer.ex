defmodule AetherPDSServer.Repositories.CommitSigner do
  @moduledoc """
  Signs and verifies ATProto repository commits using account signing keys.

  Per ATProto spec, commits are signed by:
  1. Encoding the commit data as DAG-CBOR
  2. Hashing the CBOR bytes with SHA-256
  3. Signing the hash with the account's private signing key
  """

  alias AetherPDSServer.Accounts
  alias AetherPDSServer.Crypto.SigningKey, as: SigningKeyCrypto
  alias Aether.ATProto.Commit

  @doc """
  Signs a commit using the account's active signing key.

  ## Parameters
  - commit: Aether.ATProto.Commit struct
  - account_did: The DID of the account creating the commit

  ## Returns
  - {:ok, signature_base64} - Base64-encoded signature
  - {:error, reason}
  """
  def sign_commit(%Commit{} = commit, account_did) do
    with {:ok, account} <- get_account_with_key(account_did),
         {:ok, signing_key} <- get_active_signing_key(account),
         {:ok, commit_bytes} <- encode_commit(commit),
         commit_hash <- hash_commit(commit_bytes),
         {:ok, signature} <-
           SigningKeyCrypto.sign_data(
             commit_hash,
             signing_key.private_key_encrypted,
             signing_key.key_type
           ) do
      # Encode signature as base64 for storage
      {:ok, Base.encode64(signature)}
    end
  end

  @doc """
  Verifies a commit signature.

  ## Parameters
  - commit: Aether.ATProto.Commit struct
  - signature_base64: Base64-encoded signature
  - account_did: The DID of the account that created the commit

  ## Returns
  - {:ok, true} if signature is valid
  - {:ok, false} if signature is invalid
  - {:error, reason}
  """
  def verify_commit(%Commit{} = commit, signature_base64, account_did) when is_binary(signature_base64) do
    with {:ok, signature} <- Base.decode64(signature_base64),
         {:ok, account} <- get_account_with_key(account_did),
         {:ok, signing_key} <- get_active_signing_key(account),
         {:ok, commit_bytes} <- encode_commit(commit),
         commit_hash <- hash_commit(commit_bytes),
         {:ok, valid?} <-
           SigningKeyCrypto.verify_signature(
             commit_hash,
             signature,
             signing_key.public_key_multibase,
             signing_key.key_type
           ) do
      {:ok, valid?}
    end
  end

  @doc """
  Creates a signed commit data structure.

  This is a convenience function that creates the commit object and signs it.

  ## Parameters
  - did: Repository DID
  - mst_root_cid: CID of the MST root
  - opts: Keyword list with:
    - :rev - Revision (TID)
    - :prev - Previous commit CID (optional)

  ## Returns
  - {:ok, %{commit: commit, signature: signature_base64}}
  - {:error, reason}
  """
  def create_signed_commit(did, mst_root_cid, opts \\ []) do
    # Create the commit
    commit = Commit.create(did, mst_root_cid, opts)

    # Sign it
    case sign_commit(commit, did) do
      {:ok, signature} ->
        {:ok, %{commit: commit, signature: signature}}

      error ->
        error
    end
  end

  # Private functions

  defp get_account_with_key(did) do
    case Accounts.get_account_by_did(did) do
      nil -> {:error, :account_not_found}
      account -> {:ok, AetherPDSServer.Repo.preload(account, :signing_keys)}
    end
  end

  defp get_active_signing_key(account) do
    active_key =
      Enum.find(account.signing_keys || [], fn key -> key.status == "active" end)

    case active_key do
      nil -> {:error, :no_active_signing_key}
      key -> {:ok, key}
    end
  end

  defp encode_commit(%Commit{} = commit) do
    # Encode commit as DAG-CBOR
    try do
      # Convert commit to map for CBOR encoding
      commit_map = %{
        version: commit.version,
        did: commit.did,
        rev: commit.rev,
        prev: commit.prev,
        data: commit.data
      }

      cbor_bytes = CBOR.encode(commit_map)
      {:ok, cbor_bytes}
    rescue
      e -> {:error, {:encoding_failed, e}}
    end
  end

  defp hash_commit(commit_bytes) do
    :crypto.hash(:sha256, commit_bytes)
  end
end
