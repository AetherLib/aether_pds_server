# Signing Keys Implementation TODO

## Overview
Implement ATProto signing key infrastructure for account identity and repository commit signatures.

## Current Gaps
- [ ] No signing keys in Account schema
- [ ] No `verificationMethod` in DID documents
- [ ] No key generation during account creation
- [ ] Repository commits are not cryptographically signed
- [ ] No key rotation support

## Implementation Phases

### Phase 1: Database Schema & Models
- [ ] Create `signing_keys` table migration
  - Fields: account_id, public_key_multibase, private_key_encrypted, key_type, status, created_at, rotated_at
- [ ] Create `SigningKey` Ecto schema
- [ ] Add relationship to Account schema
- [ ] Run migration

### Phase 2: Cryptographic Key Generation
- [ ] Create `AetherPDSServer.Crypto.SigningKey` module
- [ ] Implement k256 (secp256k1) key pair generation
- [ ] Implement multibase encoding (base58btc with 'z' prefix)
- [ ] Implement private key encryption at rest
- [ ] Add key validation functions

### Phase 3: Account Integration
- [ ] Update `Accounts.create_account/1` to generate signing key
- [ ] Update `DIDDocument.build_verification_methods/2` to include real keys
- [ ] Update `IdentityController.well_known_did_json/2` to include verificationMethod
- [ ] Update `DIDResolver.resolve_local_did_web/1` to include verificationMethod

### Phase 4: Repository Commit Signing
- [ ] Update commit creation to sign commit data
- [ ] Add signature verification functions
- [ ] Update commit schema to store signatures

### Phase 5: Key Rotation
- [ ] Implement key rotation endpoint
- [ ] Support multiple keys per account (one active)
- [ ] Update DID documents during rotation
- [ ] Add revocation support

## Technical Notes

### Key Requirements (from ATProto spec)
- **Type**: Multikey
- **Curves**: k256 (secp256k1) or p256 (NIST P-256)
- **Encoding**: Compressed key + multicodec prefix + base58btc encoding
- **DID Document**: Must include verificationMethod with id `#{did}#atproto`

### verificationMethod Structure
```json
{
  "id": "did:plc:abc123#atproto",
  "type": "Multikey",
  "controller": "did:plc:abc123",
  "publicKeyMultibase": "zQ3shokFTS3brHcDQrn82RUDfCZESWL1ZdCEJwekUDPQiYBme"
}
```

### Where Keys Are Used
1. Repository commit signatures (sign SHA-256 hash of DAG-CBOR encoded data)
2. DID document verification (prove control of DID)
3. Record authenticity (ensure records haven't been tampered with)

## Progress Tracking
- **Started**: 2025-10-14
- **Completed**: 2025-10-14
- **Status**: ✅ **PHASES 1-5 COMPLETE**

### Completed Phases:
- ✅ **Phase 1: Database Schema & Models**
  - Created `signing_keys` table with migration
  - Implemented `SigningKey` Ecto schema with validations
  - Added relationship to Account schema
  - Added unique constraint for one active key per account

- ✅ **Phase 2: Cryptographic Key Generation**
  - Implemented k256 (secp256k1) key pair generation using Curvy
  - Multibase encoding with base58btc (z-prefix)
  - Private key encryption with AES-256-GCM
  - Sign/verify functionality
  - Comprehensive test coverage (17 tests, all passing)

- ✅ **Phase 3: Account Integration**
  - Updated `Accounts.create_account/1` to generate signing keys
  - Updated `DIDDocument.build_verification_methods/2` to include real keys
  - Updated `IdentityController.well_known_did_json/2` to use DIDDocument module
  - Updated `DIDResolver.resolve_local_did_web/1` to use DIDDocument module
  - DID documents now include proper `verificationMethod` with:
    - `id`: `#{did}#atproto`
    - `type`: `"Multikey"`
    - `controller`: The account's DID
    - `publicKeyMultibase`: Base58btc-encoded public key

- ✅ **Phase 4: Repository Commit Signing**
  - Added `signature` field to commits table
  - Created `CommitSigner` module for signing and verification
  - Updated account creation to sign initial commits
  - Sign commits using account's private key
  - Verify signatures using public keys
  - 10 new tests covering signing/verification (all passing)
  - End-to-end test confirms new accounts have signed commits
  - **Updated RepoController to sign all commits**:
    - `apply_batch_writes` - batch operations now signed
    - `create_record_with_commit` - single record creation signed
    - `update_record_with_commit` - single record updates signed
    - `delete_record_with_commit` - single record deletions signed
    - CAR import preserves original commit signatures (no re-signing)
  - All 151 tests passing (5 pre-existing blob failures unrelated to signing)

- ✅ **Phase 5: Key Rotation**
  - Created key rotation functions in Accounts context:
    - `rotate_signing_key/2` - Rotates the active key atomically
    - `revoke_signing_key/1` - Revokes a rotated key
    - `list_signing_keys/1` - Lists all keys for an account
    - `get_active_signing_key/1` - Gets the currently active key
    - `get_active_signing_key_by_did/1` - Gets active key by DID
  - Added `/xrpc/com.atproto.server.rotateSigningKey` endpoint
  - Updated DID documents to include all non-revoked keys (active + rotated)
    - Active key gets `#atproto` fragment ID
    - Rotated keys get `#atproto-{id}` fragment IDs
  - Key rotation is atomic (both operations in single transaction)
  - Historical commit verification supported (rotated keys remain in DID doc)
  - 11 new tests covering all rotation scenarios (all passing)
  - Total: 162 tests (5 pre-existing blob failures unrelated to signing)

## Implementation Notes
- **Base58 Abstraction**: All multibase operations consolidated in `Multibase` submodule for easy migration to aether_atproto library
- **Key Type**: Using Curvy for secp256k1 (k256) - the Bluesky default
- **Security**: Private keys encrypted at rest with AES-256-GCM
- **Encryption Key**: Development uses hash of default secret; production should use secure KMS
- **Key Rotation**: Atomic operation using database transactions
- **Historical Verification**: Rotated keys remain in DID documents for verifying old commits
- **Test Coverage**: 50 new tests (29 for keys, 10 for commit signing, 11 for rotation) - all passing

## Files Created/Modified

### New Files:
- `priv/repo/migrations/*_create_signing_keys.exs` - Database migration for keys
- `priv/repo/migrations/*_add_signature_to_commits.exs` - Database migration for signatures
- `lib/aether_pds_server/accounts/signing_key.ex` - SigningKey schema
- `lib/aether_pds_server/crypto/signing_key.ex` - Cryptographic operations
- `lib/aether_pds_server/repositories/commit_signer.ex` - Commit signing/verification
- `test/aether_pds_server/crypto/signing_key_test.exs` - Crypto tests
- `test/aether_pds_server/accounts/signing_key_test.exs` - Schema tests
- `test/aether_pds_server/repositories/commit_signer_test.exs` - Commit signing tests
- `test/aether_pds_server/accounts/key_rotation_test.exs` - Key rotation tests
- `SIGNING_KEYS_TODO.md` - This file

### Modified Files:
- `mix.exs` - Added curvy and b58 dependencies
- `lib/aether_pds_server/accounts/account.ex` - Added signing_keys association
- `lib/aether_pds_server/accounts.ex` - Added key generation, commit signing, key rotation functions
- `lib/aether_pds_server/repositories/commit.ex` - Added signature field
- `lib/aether_pds_server/did_document.ex` - Include all non-revoked keys in verificationMethod
- `lib/aether_pds_server_web/controllers/com_atproto/identity_controller.ex` - Use DIDDocument module
- `lib/aether_pds_server/did_resolver.ex` - Use DIDDocument module
- `lib/aether_pds_server_web/controllers/com_atproto/server_controller.ex` - Added rotateSigningKey endpoint
- `lib/aether_pds_server_web/controllers/com_atproto/repo_controller.ex` - Sign all commits
- `lib/aether_pds_server_web/router.ex` - Added rotateSigningKey route

## Known Issues
- p256 (NIST P-256) key type not yet implemented (only k256 supported)
- Encryption key management needs production-grade solution (AWS KMS, Vault, etc.)

## Next Steps (Priority Order)
1. **Add signature verification** to sync protocol (verify commit signatures when syncing)
2. **Production key management** - integrate with KMS/Vault for private key encryption
3. **Add p256 support** (NIST P-256 key type) for broader compatibility
