defmodule AetherPDSServer.Crypto.SigningKeyTest do
  use AetherPDSServer.DataCase, async: true

  alias AetherPDSServer.Crypto.SigningKey

  describe "generate_key_pair/1" do
    test "generates a valid k256 key pair" do
      assert {:ok, key_pair} = SigningKey.generate_key_pair("k256")
      assert is_binary(key_pair.public_key_multibase)
      assert is_binary(key_pair.private_key_encrypted)

      # Public key should start with 'z' (multibase prefix)
      assert String.starts_with?(key_pair.public_key_multibase, "z")

      # Public key should be reasonably long (base58 encoded 33-byte compressed key + multicodec)
      assert String.length(key_pair.public_key_multibase) > 40

      # Encrypted private key should be base64 encoded
      assert {:ok, _decoded} = Base.decode64(key_pair.private_key_encrypted)
    end

    test "generates different keys on each call" do
      assert {:ok, key_pair1} = SigningKey.generate_key_pair("k256")
      assert {:ok, key_pair2} = SigningKey.generate_key_pair("k256")

      # Keys should be different
      assert key_pair1.public_key_multibase != key_pair2.public_key_multibase
      assert key_pair1.private_key_encrypted != key_pair2.private_key_encrypted
    end

    test "returns error for p256 (not yet supported)" do
      assert {:error, :p256_not_yet_supported} = SigningKey.generate_key_pair("p256")
    end

    test "returns error for unsupported key type" do
      assert {:error, :unsupported_key_type} = SigningKey.generate_key_pair("invalid")
    end
  end

  describe "decrypt_private_key/1" do
    test "can decrypt an encrypted private key" do
      assert {:ok, key_pair} = SigningKey.generate_key_pair("k256")
      assert {:ok, decrypted} = SigningKey.decrypt_private_key(key_pair.private_key_encrypted)

      # Decrypted key should be 32 bytes (secp256k1 private key)
      assert is_binary(decrypted)
      assert byte_size(decrypted) == 32
    end

    test "returns error for invalid encrypted key" do
      assert {:error, :invalid_encrypted_key} = SigningKey.decrypt_private_key("invalid_base64!")
    end

    test "returns error for tampered encrypted key" do
      assert {:ok, key_pair} = SigningKey.generate_key_pair("k256")

      # Tamper with the encrypted key
      tampered = String.replace(key_pair.private_key_encrypted, "A", "B", global: false)

      assert {:error, _} = SigningKey.decrypt_private_key(tampered)
    end
  end

  describe "sign_data/3 and verify_signature/4" do
    test "can sign and verify data" do
      # Generate key pair
      assert {:ok, key_pair} = SigningKey.generate_key_pair("k256")

      # Create some test data (SHA-256 hash)
      data = :crypto.hash(:sha256, "Hello, ATProto!")

      # Sign the data
      assert {:ok, signature} = SigningKey.sign_data(data, key_pair.private_key_encrypted, "k256")
      assert is_binary(signature)

      # Verify the signature
      assert {:ok, true} =
               SigningKey.verify_signature(data, signature, key_pair.public_key_multibase, "k256")
    end

    test "verification fails with wrong data" do
      assert {:ok, key_pair} = SigningKey.generate_key_pair("k256")

      # Sign data
      data = :crypto.hash(:sha256, "Hello, ATProto!")
      assert {:ok, signature} = SigningKey.sign_data(data, key_pair.private_key_encrypted, "k256")

      # Try to verify with different data
      wrong_data = :crypto.hash(:sha256, "Wrong data!")

      assert {:ok, false} =
               SigningKey.verify_signature(
                 wrong_data,
                 signature,
                 key_pair.public_key_multibase,
                 "k256"
               )
    end

    test "verification fails with wrong public key" do
      assert {:ok, key_pair1} = SigningKey.generate_key_pair("k256")
      assert {:ok, key_pair2} = SigningKey.generate_key_pair("k256")

      # Sign data with key_pair1
      data = :crypto.hash(:sha256, "Hello, ATProto!")
      assert {:ok, signature} = SigningKey.sign_data(data, key_pair1.private_key_encrypted, "k256")

      # Try to verify with key_pair2's public key
      assert {:ok, false} =
               SigningKey.verify_signature(
                 data,
                 signature,
                 key_pair2.public_key_multibase,
                 "k256"
               )
    end

    test "returns error for p256 signing" do
      assert {:error, :p256_not_yet_supported} = SigningKey.sign_data("data", "key", "p256")
    end

    test "returns error for p256 verification" do
      assert {:error, :p256_not_yet_supported} =
               SigningKey.verify_signature("data", "sig", "key", "p256")
    end
  end

  describe "Multibase module" do
    alias AetherPDSServer.Crypto.SigningKey.Multibase

    test "encode_base58btc adds 'z' prefix" do
      data = "hello"
      encoded = Multibase.encode_base58btc(data)
      assert String.starts_with?(encoded, "z")
    end

    test "decode_base58btc removes 'z' prefix and decodes" do
      data = "hello"
      encoded = Multibase.encode_base58btc(data)
      assert {:ok, decoded} = Multibase.decode_base58btc(encoded)
      assert decoded == data
    end

    test "decode_base58btc returns error for invalid prefix" do
      assert {:error, :invalid_multibase_prefix} = Multibase.decode_base58btc("xInvalidPrefix")
    end

    test "decode_base58btc returns error for invalid base58" do
      # Use invalid base58 characters (0, O, I, l are not in base58 alphabet)
      assert {:error, :invalid_base58} = Multibase.decode_base58btc("z00OOIIll")
    end

    test "roundtrip encoding/decoding" do
      original = :crypto.strong_rand_bytes(32)
      encoded = Multibase.encode_base58btc(original)
      assert {:ok, decoded} = Multibase.decode_base58btc(encoded)
      assert decoded == original
    end
  end
end
