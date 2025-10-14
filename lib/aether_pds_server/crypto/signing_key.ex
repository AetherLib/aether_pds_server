defmodule AetherPDSServer.Crypto.SigningKey do
  @moduledoc """
  Cryptographic signing key generation and management for ATProto.

  Supports:
  - k256 (secp256k1) - Default for Bluesky
  - p256 (NIST P-256) - WebCrypto compatible

  Keys are encoded using multibase with base58btc encoding (prefixed with 'z').
  Private keys are encrypted at rest using AES-256-GCM.

  ## Future Migration Note
  Base58 multibase encoding is currently handled here but will be moved to
  the `aether_atproto` library. All multibase operations are consolidated in
  the private `Multibase` module to facilitate this migration.
  """

  # TODO: Move this to aether_atproto library
  defmodule Multibase do
    @moduledoc false
    # Consolidates all base58 multibase operations for easy migration to aether_atproto

    @doc "Encode bytes as base58btc multibase (with 'z' prefix)"
    def encode_base58btc(bytes), do: "z" <> Base58.encode(bytes)

    @doc "Decode base58btc multibase string (removes 'z' prefix)"
    def decode_base58btc("z" <> rest) do
      try do
        decoded = Base58.decode(rest)
        {:ok, decoded}
      rescue
        _ -> {:error, :invalid_base58}
      end
    end

    def decode_base58btc(_), do: {:error, :invalid_multibase_prefix}
  end

  @doc """
  Generates a new signing key pair.

  ## Parameters
  - key_type: "k256" (secp256k1, default) or "p256" (NIST P-256)

  ## Returns
  - {:ok, %{public_key_multibase: String.t(), private_key_encrypted: String.t()}}
  - {:error, reason}

  ## Examples

      iex> SigningKey.generate_key_pair("k256")
      {:ok, %{
        public_key_multibase: "zQ3shokFTS3brHcDQrn82RUDfCZESWL1ZdCEJwekUDPQiYBme",
        private_key_encrypted: "..."
      }}
  """
  def generate_key_pair(key_type \\ "k256")

  def generate_key_pair("k256") do
    # Generate secp256k1 key pair using Curvy
    private_key = Curvy.generate_key()

    # Get compressed public key bytes (33 bytes for secp256k1)
    # Curvy.Key.to_pubkey returns binary directly when compressed
    public_key_bytes = Curvy.Key.to_pubkey(private_key)

    # Encode public key in multibase format
    # Multicodec prefix for secp256k1-pub: 0xe7 (231 in decimal)
    multicodec_prefix = <<0xE7, 0x01>>
    public_key_multibase = encode_multibase(multicodec_prefix <> public_key_bytes)

    # Get raw private key bytes (32 bytes)
    private_key_bytes = get_private_key_bytes(private_key)

    # Encrypt private key
    private_key_encrypted = encrypt_private_key(private_key_bytes)

    {:ok,
     %{
       public_key_multibase: public_key_multibase,
       private_key_encrypted: private_key_encrypted
     }}
  end

  def generate_key_pair("p256") do
    # P256 support would require additional dependencies
    # For now, we'll focus on k256 which is the Bluesky default
    {:error, :p256_not_yet_supported}
  end

  def generate_key_pair(_), do: {:error, :unsupported_key_type}

  @doc """
  Decrypts a private key.

  ## Parameters
  - encrypted_key: The encrypted private key string

  ## Returns
  - {:ok, decrypted_bytes}
  - {:error, reason}
  """
  def decrypt_private_key(encrypted_key) do
    try do
      # Decode base64
      decoded = Base.decode64!(encrypted_key)

      # Extract nonce (first 12 bytes), tag (next 16 bytes), ciphertext (rest)
      <<nonce::binary-size(12), tag::binary-size(16), ciphertext::binary>> = decoded

      # Get encryption key from config or environment
      encryption_key = get_encryption_key()

      # Decrypt using AES-256-GCM
      case :crypto.crypto_one_time_aead(:aes_256_gcm, encryption_key, nonce, ciphertext, "", tag,
             false
           ) do
        plaintext when is_binary(plaintext) -> {:ok, plaintext}
        _error -> {:error, :decryption_failed}
      end
    rescue
      _ -> {:error, :invalid_encrypted_key}
    end
  end

  @doc """
  Signs data using a private key.

  ## Parameters
  - data: Binary data to sign (usually SHA-256 hash)
  - private_key_encrypted: Encrypted private key
  - key_type: "k256" or "p256"

  ## Returns
  - {:ok, signature_bytes}
  - {:error, reason}
  """
  def sign_data(data, private_key_encrypted, key_type \\ "k256")

  def sign_data(data, private_key_encrypted, "k256") do
    with {:ok, private_key_bytes} <- decrypt_private_key(private_key_encrypted) do
      try do
        private_key = Curvy.Key.from_privkey(private_key_bytes)
        signature = Curvy.sign(data, private_key, hash: false, compact: true)
        {:ok, signature}
      rescue
        _ -> {:error, :signing_failed}
      end
    end
  end

  def sign_data(_data, _private_key, "p256"), do: {:error, :p256_not_yet_supported}
  def sign_data(_data, _private_key, _), do: {:error, :unsupported_key_type}

  @doc """
  Verifies a signature using a public key.

  ## Parameters
  - data: Binary data that was signed
  - signature: Signature bytes
  - public_key_multibase: Multibase-encoded public key
  - key_type: "k256" or "p256"

  ## Returns
  - {:ok, true} if valid
  - {:ok, false} if invalid
  - {:error, reason}
  """
  def verify_signature(data, signature, public_key_multibase, key_type \\ "k256")

  def verify_signature(data, signature, public_key_multibase, "k256") do
    with {:ok, public_key_bytes} <- decode_multibase_public_key(public_key_multibase) do
      try do
        public_key = Curvy.Key.from_pubkey(public_key_bytes)
        result = Curvy.verify(signature, data, public_key, hash: false)
        {:ok, result}
      rescue
        _ -> {:error, :verification_failed}
      end
    end
  end

  def verify_signature(_data, _signature, _public_key, "p256"),
    do: {:error, :p256_not_yet_supported}

  def verify_signature(_data, _signature, _public_key, _), do: {:error, :unsupported_key_type}

  # Private helper functions

  defp get_private_key_bytes(%Curvy.Key{} = key) do
    # Get raw private key bytes (32 bytes)
    Curvy.Key.to_privkey(key)
  end

  defp encode_multibase(bytes) do
    # TODO: This will move to aether_atproto library
    Multibase.encode_base58btc(bytes)
  end

  defp decode_multibase_public_key(multibase_key) do
    # TODO: This will move to aether_atproto library
    with {:ok, decoded} <- Multibase.decode_base58btc(multibase_key),
         # Remove multicodec prefix (2 bytes)
         <<_multicodec::binary-size(2), public_key_bytes::binary>> <- decoded do
      {:ok, public_key_bytes}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_multibase_key}
    end
  rescue
    _ -> {:error, :invalid_multibase_key}
  end

  defp encrypt_private_key(private_key_bytes) do
    # Generate random nonce (12 bytes for GCM)
    nonce = :crypto.strong_rand_bytes(12)

    # Get encryption key from config
    encryption_key = get_encryption_key()

    # Encrypt using AES-256-GCM
    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(
        :aes_256_gcm,
        encryption_key,
        nonce,
        private_key_bytes,
        "",
        true
      )

    # Combine nonce + tag + ciphertext and encode as base64
    (nonce <> tag <> ciphertext)
    |> Base.encode64()
  end

  defp get_encryption_key do
    # Get encryption key from config or environment
    # In production, this should be stored securely (e.g., AWS KMS, HashiCorp Vault)
    case Application.get_env(:aether_pds_server, :signing_key_encryption_key) do
      nil ->
        # Generate a default key for development (32 bytes for AES-256)
        # WARNING: In production, use a secure key management system
        :crypto.hash(:sha256, "aether_pds_server_default_signing_key_secret")

      key when is_binary(key) and byte_size(key) == 32 ->
        key

      key when is_binary(key) ->
        # Hash the key to ensure it's 32 bytes
        :crypto.hash(:sha256, key)
    end
  end
end
