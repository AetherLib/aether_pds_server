# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Aether PDS Server is an AT Protocol (ATProto) Personal Data Server (PDS) implementation built with Phoenix/Elixir. It provides OAuth-based authentication with DPoP (Demonstrating Proof-of-Possession), repository management with Merkle Search Trees (MST), and full ATProto sync protocol support for federation.

## Development Commands

### Setup
```bash
mix setup                    # Install deps, create DB, run migrations, seed data
mix ecto.setup              # Create DB, migrate, seed
mix ecto.reset              # Drop and recreate DB
```

### Development
```bash
mix phx.server              # Start Phoenix server (localhost:4000)
iex -S mix phx.server       # Start with IEx console
mix compile                 # Compile source files
mix precommit               # Run before committing (compile with warnings as errors, unlock unused deps, format, test)
```

### Database
```bash
mix ecto.create             # Create database
mix ecto.migrate            # Run migrations
mix ecto.rollback           # Rollback last migration
mix ecto.gen.migration name # Generate new migration
```

### Testing
```bash
mix test                    # Run all tests (auto-creates test DB)
mix test path/to/test.exs   # Run specific test file
mix test --failed           # Run only previously failed tests
```

## Architecture Overview

### Core Context Modules

The application follows Phoenix context patterns with three main business logic contexts:

1. **AetherPDSServer.Accounts** (`lib/aether_pds_server/accounts.ex`)
   - Account creation and management
   - Authentication (handle/email + password)
   - Password hashing with Argon2
   - Simple DID generation (did:plc format)
   - Delegates token operations to OAuth module

2. **AetherPDSServer.Repositories** (`lib/aether_pds_server/repositories.ex`)
   - Repository CRUD operations
   - Commit history tracking (with CIDs)
   - Record operations (collection-based, with pagination/cursors)
   - MST (Merkle Search Tree) block storage
   - Event stream for sync protocol
   - Blob storage and reference tracking

3. **AetherPDSServer.OAuth** (`lib/aether_pds_server/oauth.ex`)
   - OAuth authorization flow with PKCE
   - DPoP (Demonstrating Proof-of-Possession) verification
   - Access token lifecycle (with JKT binding)
   - Refresh token management
   - Client metadata validation
   - Token cleanup utilities

### Data Models

**Repository System:**
- `Repository` - Root entity identified by DID, tracks head_cid
- `Commit` - Immutable repository snapshots with CIDs
- `Record` - Stored by (repository_did, collection, rkey)
- `MstBlock` - Merkle Search Tree node storage
- `Event` - Sequential event log for sync protocol
- `Blob` - Binary data storage with CID addressing
- `BlobRef` - Many-to-many relationship between blobs and records

**Auth System:**
- `Account` - User accounts with DID, handle, email, password_hash
- `AuthorizationCode` - Short-lived OAuth codes with PKCE challenge
- `AccessToken` - DPoP-bound tokens with JKT (JSON Key Thumbprint)
- `RefreshToken` - Long-lived tokens for session renewal

### Router Architecture

The router (`lib/aether_pds_server_web/router.ex`) is organized into four scopes:

1. **OAuth Endpoints** (public) - Token flow, authorization, login
2. **Public XRPC** - Server description, repo reads, sync protocol, identity resolution
3. **Authenticated XRPC** - Account/session management, repo writes, blob uploads
4. **Admin XRPC** - Sync notifications, crawl requests

All authenticated routes use `RequireAuth` plug that validates DPoP-bound access tokens.

### ATProto Integration

This server integrates with the `aether_atproto` library (v0.1.2) for:
- DPoP cryptographic operations (`Aether.ATProto.Crypto.DPoP`)
- ATProto protocol compliance
- CID/CBOR handling

### Authentication Flow

1. User authenticates via handle/email + password
2. OAuth flow generates authorization code with PKCE
3. Client exchanges code for access/refresh tokens
4. Access tokens are DPoP-bound (tied to client's public key via JKT)
5. All authenticated requests must include DPoP proof JWT with `ath` claim

## Important Development Notes

### Mix Aliases
- Always use `mix precommit` before committing changes
- This runs: compile with warnings as errors, unlock unused deps, format code, run tests

### HTTP Requests
- Use `:req` (Req) library for all HTTP requests
- Avoid `:httpoison`, `:tesla`, `:httpc` - Req is the standard

### Database Queries
- Always preload Ecto associations when accessing them in templates
- Use `import Ecto.Query` in any file with database queries

### Phoenix v1.8 Specifics
- Refer to AGENTS.md for comprehensive Phoenix/Elixir guidelines
- Key points:
  - Use scope aliases properly in router (avoid duplicate module prefixes)
  - Access changeset fields with `Ecto.Changeset.get_field/2`
  - Elixir lists don't support index access - use `Enum.at/2`
  - Variables are immutable but can be rebound - always bind block expression results

### Token Management
- Access tokens expire after 1 hour
- Refresh tokens expire after 30 days
- All tokens support revocation
- Use `OAuth.cleanup_expired_tokens/0` for periodic cleanup (not currently scheduled)

### Testing Database
- Test environment auto-creates database on `mix test`
- No need to manually manage test DB

### End-to-End Testing
- `./test_e2e.sh` - Run full end-to-end test (requires server running)
- Tests: account creation → repository creation → record CRUD → CAR export
- Requires `jq` for JSON parsing

## Project Dependencies

Key dependencies:
- `phoenix` ~> 1.8.1
- `ecto_sql` ~> 3.13, `postgrex` (PostgreSQL database)
- `bandit` ~> 1.5 (HTTP server)
- `aether_atproto` ~> 0.1.2 (ATProto protocol library)
- `joken` ~> 2.6, `jose` ~> 1.11 (JWT/DPoP handling)
- `argon2_elixir` ~> 4.0 (password hashing)
- `req` ~> 0.5 (HTTP client)
