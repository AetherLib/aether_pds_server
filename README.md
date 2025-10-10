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

**Federation & Discovery** (✅ Core Implemented)
- ✅ DID resolution via PLC directory (did:plc and did:web)
- ✅ Handle resolution (HTTPS well-known + DNS TXT records)
- ✅ DID document generation and validation
- ✅ Remote PDS discovery from handles/DIDs
- ✅ Cross-server record fetching
- ✅ Service endpoint extraction
- ⚠️ **Missing**: Relay integration, firehose subscriptions, commit verification

**App.bsky Endpoints** (✅ 80% Complete)
- ✅ Feed endpoints (timeline, author feed, post thread, search, likes, reposts)
- ✅ Actor endpoints (profiles, search, preferences)
- ✅ Labeler endpoints (moderation service discovery)
- ✅ Engagement tracking (likes, reposts, replies, quotes)
- ✅ Viewer state (follow status, like/repost status)
- ⚠️ **Missing**: Feed generators execution, list feeds, suggested feeds

### 📋 Roadmap

**Phase 1: App.bsky Social Features** (✅ 80% Complete)
- [x] Feed endpoints (timeline, author feed, post thread)
- [x] Actor endpoints (profiles, search, preferences)
- [x] Labeler endpoints (moderation service)
- [x] Engagement tracking (likes, reposts, replies)
- [x] Viewer state (relationships, interactions)
- [ ] Feed generators (execution engine)
- [ ] List feeds and suggested feeds
- [ ] Graph endpoints (blocks, mutes)

**Phase 2: Federation Core** (✅ 60% Complete)
- [x] DID resolution (plc.directory integration)
- [x] Handle resolution (HTTPS + DNS)
- [x] DID document generation
- [x] Cross-server PDS discovery
- [x] Remote record fetching
- [ ] Commit signature verification
- [ ] Relay server integration
- [ ] AppView subscriptions
- [ ] Firehose event stream subscriptions

**Phase 3: Performance & Reliability**
- [ ] Redis caching layer
- [ ] Background job processing (Oban)
- [ ] Database query optimization (feed queries, engagement counts)
- [ ] Token cleanup automation
- [ ] Blob garbage collection

**Phase 4: Security Enhancements**
- [ ] Rate limiting
- [ ] Email verification
- [ ] Account recovery flows
- [ ] Multi-client OAuth support
- [ ] IP-based access controls

**Phase 5: Data Management**
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

**Phase 6: Observability**
- [ ] Prometheus metrics
- [ ] Structured logging
- [ ] Admin dashboard
- [ ] Audit logging
- [ ] Performance monitoring

**Phase 7: Developer Experience**
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

**Federation** (`lib/aether_pds_server/federation.ex`)
- Remote PDS discovery
- Cross-server record fetching
- Repository verification (basic)

**DID Resolution** (`lib/aether_pds_server/did_resolver.ex`)
- Handle → DID resolution
- DID → DID document resolution
- Service endpoint extraction
- Support for did:plc and did:web

**DID Documents** (`lib/aether_pds_server/did_document.ex`)
- DID document generation
- Validation
- Service endpoint management

**App.bsky Controllers**
- **FeedController** (`lib/aether_pds_server_web/controllers/app_bsky/feed_controller.ex`)
  - Timeline feeds (getTimeline)
  - Author feeds (getAuthorFeed)
  - Post threads (getPostThread)
  - Feed search (searchPosts)
  - Engagement (getLikes, getRepostedBy)
- **ActorController** (`lib/aether_pds_server_web/controllers/app_bsky/actor_controller.ex`)
  - Profile views (getProfile, getProfiles)
  - Actor search (searchActors, searchActorsTypeahead)
  - Preferences (getPreferences, putPreferences)
- **LabelerController** (`lib/aether_pds_server_web/controllers/app_bsky/labeler_controller.ex`)
  - Moderation service discovery (getServices)
  - Label policies and definitions

### API Structure

**Public Endpoints** (no auth required)
- Server description
- Account creation & login
- Repository reads
- Sync protocol endpoints
- Identity resolution
- Actor profiles and search
- Feed views (public posts)

**Authenticated Endpoints** (require access token)
- Session management
- Repository writes
- Record operations
- Blob uploads
- Timeline feeds
- Preferences
- Engagement actions

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

**Status**: Active Development | **Version**: 0.2.0 | **Phase**: App.bsky Social Features (80% Complete)
