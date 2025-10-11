#TODO: fix pds_endpoint logic and use the Phoenix App to generate the endpoint for any links that need to be created

# Aether PDS Server

A **Personal Data Server (PDS)** implementation for the AT Protocol (ATProto), built with Phoenix/Elixir. This server provides the core PDS functionality as defined by the [official Bluesky PDS specification](https://github.com/bluesky-social/atproto/tree/main/packages/pds).

## ⚠️ Architecture Note

This implementation follows a **standalone PDS architecture** that differs from the official Bluesky PDS:

- **Official PDS**: Thin server that proxies social features to AppView with "read-after-write" pattern
- **Our PDS**: Self-contained server that implements social features locally (no AppView dependency)

**Implications:**
- ✅ **Works standalone** - Full functionality without external services
- ✅ **Good for**: Personal use, development, testing, small communities
- ⚠️ **Trade-off**: Some endpoints (feeds, graph, notifications) are implemented locally but belong in AppView per official architecture
- 📝 **See**: `PDS_COMPARISON.md` for detailed architectural analysis

**Router Annotations**: Check `lib/aether_pds_server_web/router.ex` for endpoint scope markers:
- `✅ CORRECT` - Official PDS scope
- `🔄 PROXY + RAW` - Should proxy to AppView in federated mode
- `❌ APPVIEW ONLY` - Not in official PDS (implemented for standalone mode)

## Features

### ✅ Core PDS Features (Official Scope)

**com.atproto.server.*** - Authentication & Account Management**
- ✅ OAuth 2.0 authorization flow with PKCE
- ✅ DPoP (Demonstrating Proof-of-Possession) token binding
- ✅ Account creation (`createAccount`)
- ✅ Session management (`createSession`, `refreshSession`, `getSession`, `deleteSession`)
- ✅ Server description (`describeServer`)
- ✅ App passwords (`createAppPassword`, `listAppPasswords`, `revokeAppPassword`)
- ✅ Account lifecycle (`activateAccount`, `deactivateAccount`, `deleteAccount`, `requestAccountDelete`)
- ✅ Service auth (`getServiceAuth`)
- ✅ Signing key reservation (`reserveSigningKey`)
- ⚠️ **Skipped** (email functionality deferred):
  - Email verification (`confirmEmail`, `requestEmailConfirmation`)
  - Password reset (`resetPassword`, `requestPasswordReset`)
  - Email updates (`updateEmail`, `requestEmailUpdate`)

**com.atproto.repo.*** - Repository Management**
- ✅ Merkle Search Tree (MST) based data structure
- ✅ CID-based content addressing
- ✅ Record operations (`createRecord`, `putRecord`, `deleteRecord`, `getRecord`, `listRecords`)
- ✅ Repository metadata (`describeRepo`)
- ✅ Batch operations (`applyWrites`)
- ✅ Blob upload (`uploadBlob`)
- ✅ Repository import (`importRepo`)
- ✅ Blob sync helper (`listMissingBlobs`)

**com.atproto.sync.*** - Sync Protocol**
- ✅ CAR (Content Addressable aRchive) export (`getRepo`)
- ✅ Commit tracking (`getLatestCommit`)
- ✅ Block-level access (`getBlocks`, `getRecord`)
- ✅ Blob access (`getBlob`, `listBlobs`)
- ✅ Crawl coordination (`notifyOfUpdate`, `requestCrawl`)

**com.atproto.identity.*** - Identity Resolution**
- ✅ Handle → DID resolution (`resolveHandle`)
- ✅ DID → DID document resolution (`resolveDid`)
- ✅ DID document generation and validation
- ✅ Service endpoint extraction
- ✅ Support for did:plc and did:web

**OAuth & DPoP**
- ✅ OAuth authorization server metadata
- ✅ Token endpoint with DPoP binding
- ✅ Token revocation
- ✅ JKT (JSON Key Thumbprint) validation
- ✅ Access token lifecycle (1 hour)
- ✅ Refresh token lifecycle (30 days)

**Federation**
- ✅ Remote PDS discovery from handles/DIDs
- ✅ Cross-server record fetching
- ✅ Repository verification (basic)
- ⚠️ **Future**: Relay integration, firehose subscriptions, commit verification

### 🔄 Extended Features (Standalone Mode)

**Note**: These features are implemented locally but belong in AppView per official architecture. They enable standalone operation without an AppView service.

**app.bsky.actor.*** - Actor Features**
- ✅ Profile views (`getProfile`, `getProfiles`) - *Should proxy to AppView*
- ✅ Actor search (`searchActors`, `searchActorsTypeahead`) - *Should proxy to AppView*
- ✅ Preferences (`getPreferences`, `putPreferences`) - *Correct in PDS*

**app.bsky.feed.*** - Feed Features**
- ✅ Timeline (`getTimeline`) - *Should proxy to AppView*
- ✅ Author feed (`getAuthorFeed`) - *Should proxy to AppView*
- ✅ Post threads (`getPostThread`) - *Should proxy to AppView*
- ✅ Feed search (`searchPosts`) - *Should proxy to AppView*
- ✅ Engagement views (`getLikes`, `getRepostedBy`) - *Should proxy to AppView*

**app.bsky.graph.*** - Graph Features**
- ✅ Follows (`getFollowers`, `getFollows`) - *AppView only in official PDS*
- ✅ Blocks/Mutes (`getBlocks`, `getMutes`, `muteActor`, `unmuteActor`) - *AppView only*
- ✅ Relationships (`getRelationships`) - *AppView only*

**app.bsky.notification.*** - Notifications**
- ✅ List/count (`listNotifications`, `getUnreadCount`) - *AppView only in official PDS*
- ✅ Mark seen (`updateSeen`) - *AppView only*

**app.bsky.labeler.*** - Moderation**
- ✅ Service discovery (`getServices`) - *Should proxy to AppView*

**User Interface** (Development)
- ✅ Account registration (LiveView)
- ✅ OAuth consent flow (LiveView)
- ✅ Login interface (LiveView)

### 📋 Roadmap

**Phase 1: Complete Core PDS Endpoints** ✅ **COMPLETE**

All non-email endpoints implemented:
- [x] App passwords (`createAppPassword`, `listAppPasswords`, `revokeAppPassword`)
- [x] Repository import (`importRepo`)
- [x] Account lifecycle (`activateAccount`, `deactivateAccount`, `deleteAccount`, `requestAccountDelete`)
- [x] Service auth (`getServiceAuth`)
- [x] Signing key reservation (`reserveSigningKey`)
- [x] Blob sync helper (`listMissingBlobs`)

Email endpoints deferred (not critical for core functionality):
- [ ] Email verification (`confirmEmail`, `requestEmailConfirmation`)
- [ ] Password reset (`resetPassword`, `requestPasswordReset`)
- [ ] Email updates (`updateEmail`, `requestEmailUpdate`)

**Phase 2: Production Readiness**
- [ ] Rate limiting (DDoS protection)
- [ ] Token cleanup automation (scheduled job)
- [ ] Proper logging (structured)
- [ ] Health checks and monitoring
- [ ] Docker deployment
- [ ] Environment-based configuration

**Phase 3: Blob Storage Enhancement**
- [ ] Object storage integration (S3/MinIO/local filesystem)
- [ ] Blob retrieval endpoints
- [ ] Proper CIDv1 generation with multihash
- [ ] Blob size limits and validation
- [ ] Blob garbage collection
- [ ] Blob virus scanning

**Phase 4: Federation Enhancement**
- [ ] Commit signature verification
- [ ] Relay server integration
- [ ] Firehose event stream subscriptions
- [ ] Repository backup/restore

**Phase 5: Optional AppView Integration**
- [ ] AppView proxy implementation
- [ ] Read-after-write (RAW) pattern
- [ ] Configurable standalone vs federated mode
- [ ] AppView client module

**Future: Beyond PDS Scope**
- [ ] Separate AppView service (if needed)
- [ ] Feed generator execution engine
- [ ] Advanced moderation tools
- [ ] Analytics and metrics

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
- App password management (create, list, revoke)
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

## Documentation

- **`PDS_COMPARISON.md`** - Detailed comparison with official Bluesky PDS
- **`CLAUDE.md`** - Development guidelines and project context
- **Router annotations** - Endpoint scope markers in `lib/aether_pds_server_web/router.ex`

---

**Status**: Active Development | **Version**: 0.2.0
**Architecture**: Standalone PDS (with AppView features for development)
**Completeness**: Core PDS 100% (all non-email endpoints complete, 6 email endpoints deferred) | Extended Features ~80%
