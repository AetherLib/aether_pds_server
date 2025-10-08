# Aether PDS Server

A Personal Data Server (PDS) implementation for the AT Protocol (ATProto), built with Phoenix/Elixir. This server enables decentralized social networking by providing users with their own data repository that federates with other ATProto services.

## Features

### ✅ Implemented

**Authentication & Authorization**
- OAuth 2.0 authorization flow with PKCE
- DPoP (Demonstrating Proof-of-Possession) token binding
- Access token lifecycle management (1 hour expiry)
- Refresh token support (30 day expiry)
- Session management endpoints

**Repository Management**
- Merkle Search Tree (MST) based data structure
- CID-based content addressing
- Commit history tracking
- Repository CRUD operations
- Record versioning

**Data Storage**
- Record operations (create, read, update, delete)
- Collection-based organization
- Pagination with cursor support

**Blob Storage** (⚠️ Basic Implementation)
- Upload endpoint (stores in PostgreSQL)
- CID generation (simplified)
- Blob metadata tracking
- Reference tracking schema
- ⚠️ **Missing**: Object storage (S3/MinIO), retrieval endpoints, proper CIDv1, size limits

**Sync Protocol**
- Event stream for repository changes
- CAR (Content Addressable aRchive) export support
- Repository snapshots
- Block-level data access

**User Interface**
- Account registration (LiveView)
- OAuth consent flow (LiveView)
- Login interface (LiveView)

### 🚧 In Progress

**Federation & Discovery**
- DID resolution via PLC directory
- Relay/AppView communication
- Webhook notifications for commits
- Firehose event subscriptions

### 📋 Roadmap

**Phase 1: Federation Core**
- [ ] DID resolution and verification
- [ ] Relay server integration
- [ ] AppView subscriptions
- [ ] Cross-server identity resolution
- [ ] PLC directory integration

**Phase 2: Performance & Reliability**
- [ ] Redis caching layer
- [ ] Background job processing (Oban)
- [ ] Database query optimization
- [ ] Token cleanup automation
- [ ] Blob garbage collection

**Phase 3: Security Enhancements**
- [ ] Rate limiting
- [ ] Email verification
- [ ] Account recovery flows
- [ ] Multi-client OAuth support
- [ ] IP-based access controls

**Phase 4: Data Management**
- [ ] Object storage integration (S3/MinIO/local filesystem)
- [ ] Blob retrieval endpoints
- [ ] Proper CIDv1 generation with multihash
- [ ] Blob size limits and validation
- [ ] Blob-to-record linking implementation
- [ ] Blob deduplication
- [ ] Blob garbage collection
- [ ] Lexicon schema validation
- [ ] Repository backup/restore
- [ ] Data retention policies
- [ ] Blob virus scanning

**Phase 5: Observability**
- [ ] Prometheus metrics
- [ ] Structured logging
- [ ] Admin dashboard
- [ ] Audit logging
- [ ] Performance monitoring

**Phase 6: Developer Experience**
- [ ] OpenAPI documentation
- [ ] Client SDK generation
- [ ] GraphQL API layer
- [ ] WebSocket subscriptions
- [ ] Docker deployment

## Quick Start

### Prerequisites

- Elixir 1.14+
- Phoenix 1.8+
- PostgreSQL 14+
- Erlang/OTP 25+

### Installation

```bash
# Clone the repository
git clone <repository-url>
cd aether_pds_server

# Install dependencies and setup database
mix setup

# Start the server
mix phx.server
```

The server will be available at [http://localhost:4000](http://localhost:4000)

### Development Commands

```bash
# Setup (install deps, create DB, run migrations, seed)
mix setup

# Run tests
mix test

# Pre-commit checks (compile with warnings as errors, format, test)
mix precommit

# Start interactive shell with server
iex -S mix phx.server

# Database migrations
mix ecto.migrate
mix ecto.rollback
mix ecto.gen.migration <name>
```

### End-to-End Testing

```bash
# Run full integration test
./test_e2e.sh
```

Tests account creation → repository creation → record CRUD → CAR export. Requires `jq`.

## Architecture

### Core Contexts

**Accounts** (`lib/aether_pds_server/accounts.ex`)
- User account management
- Authentication (handle/email + password)
- Password hashing with Argon2
- DID generation (did:plc format)

**Repositories** (`lib/aether_pds_server/repositories.ex`)
- Repository operations
- Commit tracking with CIDs
- Record management
- MST block storage
- Event stream
- Blob storage

**OAuth** (`lib/aether_pds_server/oauth.ex`)
- Authorization flows
- DPoP verification
- Token lifecycle
- Client validation

### API Structure

**Public Endpoints** (no auth required)
- Server description
- Account creation & login
- Repository reads
- Sync protocol endpoints
- Identity resolution

**Authenticated Endpoints** (require access token)
- Session management
- Repository writes
- Record operations
- Blob uploads

**Admin Endpoints** (require admin privileges)
- Sync administration
- Crawl requests

## Configuration

Key environment variables:

```elixir
# config/runtime.exs
config :aether_pds_server, AetherPDSServerWeb.Endpoint,
  url: [host: System.get_env("PHX_HOST") || "localhost"],
  http: [port: String.to_integer(System.get_env("PORT") || "4000")]

config :aether_pds_server, AetherPDSServer.Repo,
  url: System.get_env("DATABASE_URL")
```

## API Examples

### Create Account

```bash
curl -X POST http://localhost:4000/xrpc/com.atproto.server.createAccount \
  -H "Content-Type: application/json" \
  -d '{
    "handle": "alice.example.com",
    "email": "alice@example.com",
    "password": "secure-password-123"
  }'
```

### Create Session (Login)

```bash
curl -X POST http://localhost:4000/xrpc/com.atproto.server.createSession \
  -H "Content-Type: application/json" \
  -d '{
    "identifier": "alice.example.com",
    "password": "secure-password-123"
  }'
```

### Create Record

```bash
curl -X POST http://localhost:4000/xrpc/com.atproto.repo.createRecord \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <access_token>" \
  -d '{
    "repo": "<did>",
    "collection": "app.bsky.feed.post",
    "record": {
      "text": "Hello, ATProto!",
      "createdAt": "2024-01-01T00:00:00.000Z"
    }
  }'
```

## Testing

```bash
# Run all tests
mix test

# Run specific test file
mix test test/aether_pds_server_web/controllers/server_controller_test.exs

# Run with coverage
mix test --cover

# Run only failed tests
mix test --failed
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Run `mix precommit` before committing
4. Submit a pull request

## Technical Stack

- **Framework**: Phoenix 1.8
- **Language**: Elixir
- **Database**: PostgreSQL with Ecto
- **HTTP Server**: Bandit
- **Authentication**: Joken (JWT), JOSE (DPoP)
- **Password Hashing**: Argon2
- **HTTP Client**: Req
- **ATProto Library**: aether_atproto 0.1.2

## Resources

- [AT Protocol Specification](https://atproto.com/)
- [Phoenix Framework Documentation](https://hexdocs.pm/phoenix)
- [Elixir Documentation](https://elixir-lang.org/docs.html)

## License

[Add your license here]

## Related Projects

- [aether_atproto](https://github.com/your-org/aether_atproto) - ATProto library for Elixir
- [Bluesky](https://bsky.app/) - Reference implementation

---

**Status**: Active Development | **Version**: 0.1.1
