# PDS Implementation Comparison

**Date**: 2025-10-09
**Source**: [Bluesky ATProto PDS](https://github.com/bluesky-social/atproto/tree/main/packages/pds)
**Target**: Aether PDS Server (Elixir/Phoenix)

## Executive Summary

After reviewing the official Bluesky PDS source code, our implementation is **architecturally different** from the official PDS in several key ways:

### ✅ What We Got Right
- All `com.atproto` core endpoints (repo, server, sync)
- OAuth/DPoP authentication flow
- Repository management with MST
- Proper CID generation
- Federation (DID resolution, handle resolution)

### ⚠️ Critical Architectural Differences

1. **app.bsky Endpoints**: Official PDS **proxies** most app.bsky endpoints to AppView with "read-after-write" pattern
   - We implemented them **directly** in the PDS
   - This works but is not how Bluesky does it

2. **Notifications**: Official PDS only has `registerPush` (proxies other endpoints to AppView)
   - We implemented full notification generation in PDS
   - This is incorrect architecture

3. **Feed/Actor Endpoints**: Official PDS proxies to AppView with local write injection
   - We generate everything locally
   - This works for single-user PDS but not canonical

---

## Detailed Endpoint Comparison

### com.atproto.server.*

| Endpoint | Official PDS | Our PDS | Status | Notes |
|----------|-------------|---------|--------|-------|
| `createAccount` | ✅ Direct | ✅ Direct | ✅ Match | Returns `{handle, did, didDoc, accessJwt, refreshJwt}` |
| `createSession` | ✅ Direct | ✅ Direct | ✅ Match | Session management |
| `refreshSession` | ✅ Direct | ✅ Direct | ✅ Match | Token refresh |
| `getSession` | ✅ Direct | ✅ Direct | ✅ Match | Current session |
| `deleteSession` | ✅ Direct | ✅ Direct | ✅ Match | Logout |
| `describeServer` | ✅ Direct | ✅ Direct | ✅ Match | Server metadata |
| `createAppPassword` | ✅ Direct | ❌ Missing | ❌ TODO | App-specific passwords |
| `listAppPasswords` | ✅ Direct | ❌ Missing | ❌ TODO | List app passwords |
| `revokeAppPassword` | ✅ Direct | ❌ Missing | ❌ TODO | Revoke app password |
| `activateAccount` | ✅ Direct | ❌ Missing | ❌ TODO | Reactivate account |
| `deactivateAccount` | ✅ Direct | ❌ Missing | ❌ TODO | Temporarily deactivate |
| `deleteAccount` | ✅ Direct | ❌ Missing | ❌ TODO | Permanent deletion |
| `requestAccountDelete` | ✅ Direct | ❌ Missing | ❌ TODO | Request deletion token |
| `confirmEmail` | ✅ Direct | ❌ Missing | ❌ TODO | Email verification |
| `requestEmailConfirmation` | ✅ Direct | ❌ Missing | ❌ TODO | Send confirmation email |
| `requestEmailUpdate` | ✅ Direct | ❌ Missing | ❌ TODO | Update email |
| `updateEmail` | ✅ Direct | ❌ Missing | ❌ TODO | Confirm email update |
| `resetPassword` | ✅ Direct | ❌ Missing | ❌ TODO | Reset password |
| `requestPasswordReset` | ✅ Direct | ❌ Missing | ❌ TODO | Request reset token |
| `getServiceAuth` | ✅ Direct | ❌ Missing | ❌ TODO | Service authentication |
| `reserveSigningKey` | ✅ Direct | ❌ Missing | ❌ TODO | Reserve signing key |

### com.atproto.repo.*

| Endpoint | Official PDS | Our PDS | Status | Notes |
|----------|-------------|---------|--------|-------|
| `createRecord` | ✅ Direct | ✅ Direct | ✅ Match | Create repository record |
| `putRecord` | ✅ Direct | ✅ Direct | ✅ Match | Update record |
| `deleteRecord` | ✅ Direct | ✅ Direct | ✅ Match | Delete record |
| `getRecord` | ✅ Direct | ✅ Direct | ✅ Match | Get single record |
| `listRecords` | ✅ Direct | ✅ Direct | ✅ Match | List records with pagination |
| `describeRepo` | ✅ Direct | ✅ Direct | ✅ Match | Repository metadata |
| `uploadBlob` | ✅ Direct | ✅ Direct | ✅ Match | Upload blob |
| `applyWrites` | ✅ Direct | ✅ Direct | ✅ Match | Batch operations |
| `importRepo` | ✅ Direct | ❌ Missing | ❌ TODO | Import CAR file |
| `listMissingBlobs` | ✅ Direct | ❌ Missing | ❌ TODO | List missing blobs |

### com.atproto.sync.*

| Endpoint | Official PDS | Our PDS | Status | Notes |
|----------|-------------|---------|--------|-------|
| `getRepo` | ✅ Direct | ✅ Direct | ✅ Match | Get repo as CAR |
| `getLatestCommit` | ✅ Direct | ✅ Direct | ✅ Match | Latest commit CID |
| `getRecord` | ✅ Direct | ✅ Direct | ✅ Match | Get record for sync |
| `getBlocks` | ✅ Direct | ✅ Direct | ✅ Match | Get MST blocks |
| `getBlob` | ✅ Direct | ✅ Direct | ✅ Match | Get blob |
| `listBlobs` | ✅ Direct | ✅ Direct | ✅ Match | List blobs |
| `notifyOfUpdate` | ✅ Direct | ✅ Direct | ✅ Match | Notify of update |
| `requestCrawl` | ✅ Direct | ✅ Direct | ✅ Match | Request crawl |

### com.atproto.identity.*

| Endpoint | Official PDS | Our PDS | Status | Notes |
|----------|-------------|---------|--------|-------|
| `resolveHandle` | ✅ Direct | ✅ Direct | ✅ Match | Handle → DID |
| `resolveDid` | ✅ Direct | ✅ Direct | ✅ Match | DID → DID Document |

### app.bsky.actor.* (⚠️ Architecture Difference)

| Endpoint | Official PDS | Our PDS | Status | Notes |
|----------|-------------|---------|--------|-------|
| `getProfile` | 🔄 Proxy + RAW | ✅ Direct | ⚠️ Works | Should proxy to AppView |
| `getProfiles` | 🔄 Proxy + RAW | ✅ Direct | ⚠️ Works | Should proxy to AppView |
| `getPreferences` | ✅ Direct | ✅ Direct | ✅ Match | Local preferences |
| `putPreferences` | ✅ Direct | ✅ Direct | ✅ Match | Update preferences |
| `searchActors` | 🔄 Proxy | ✅ Direct | ⚠️ Works | Should proxy to AppView |
| `searchActorsTypeahead` | 🔄 Proxy | ✅ Direct | ⚠️ Works | Should proxy to AppView |
| `getSuggestions` | 🔄 Proxy | ✅ Direct | ⚠️ Works | Should proxy to AppView |

**Legend:**
- 🔄 Proxy + RAW = Proxies to AppView with "read-after-write" local data injection
- ✅ Direct = Handles locally
- ⚠️ Works = Functions correctly but architecture differs

### app.bsky.feed.* (⚠️ Architecture Difference)

| Endpoint | Official PDS | Our PDS | Status | Notes |
|----------|-------------|---------|--------|-------|
| `getTimeline` | 🔄 Proxy + RAW | ✅ Direct | ⚠️ Works | Should proxy to AppView |
| `getAuthorFeed` | 🔄 Proxy + RAW | ✅ Direct | ⚠️ Works | Should proxy to AppView |
| `getActorLikes` | 🔄 Proxy + RAW | ✅ Direct | ⚠️ Works | Should proxy to AppView |
| `getPostThread` | 🔄 Proxy + RAW | ✅ Direct | ⚠️ Works | Should proxy to AppView |
| `getFeed` | 🔄 Proxy | ✅ Direct | ⚠️ Works | Should proxy to AppView |
| All others | 🔄 Proxy | ✅ Direct | ⚠️ Works | Should proxy to AppView |

### app.bsky.graph.* (✅ Correct in Our Implementation)

| Endpoint | Official PDS | Our PDS | Status | Notes |
|----------|-------------|---------|--------|-------|
| `getFollowers` | ❌ Not in PDS | ✅ Direct | ⚠️ Extra | AppView only in official |
| `getFollows` | ❌ Not in PDS | ✅ Direct | ⚠️ Extra | AppView only in official |
| `getBlocks` | ❌ Not in PDS | ✅ Direct | ⚠️ Extra | AppView only in official |
| `getMutes` | ❌ Not in PDS | ✅ Direct | ⚠️ Extra | AppView only in official |
| `muteActor` | ❌ Not in PDS | ✅ Direct | ⚠️ Extra | AppView only in official |
| `unmuteActor` | ❌ Not in PDS | ✅ Direct | ⚠️ Extra | AppView only in official |
| etc. | ❌ Not in PDS | ✅ Direct | ⚠️ Extra | AppView only in official |

### app.bsky.notification.* (❌ Incorrect Architecture)

| Endpoint | Official PDS | Our PDS | Status | Notes |
|----------|-------------|---------|--------|-------|
| `listNotifications` | ❌ Not in PDS | ✅ Direct | ❌ Wrong | AppView only |
| `getUnreadCount` | ❌ Not in PDS | ✅ Direct | ❌ Wrong | AppView only |
| `updateSeen` | ❌ Not in PDS | ✅ Direct | ❌ Wrong | AppView only |
| `registerPush` | ✅ Proxy Helper | ✅ Stub | ⚠️ Incomplete | Should proxy to AppView |

---

## Read-After-Write (RAW) Pattern

The official PDS uses a clever "read-after-write" pattern:

1. **Proxy to AppView**: Forward request to AppView service
2. **Check Local Writes**: Look for recent writes not yet in AppView
3. **Merge Results**: Inject local writes into AppView response
4. **Return to Client**: Client sees eventual consistency

This ensures:
- AppView handles heavy aggregation (followers, likes, feeds)
- PDS injects immediate writes (posts you just created)
- Client sees consistent view

**Our Implementation**: We do everything locally, which works for single-user PDS but:
- Doesn't scale to network-wide queries (who follows X across all servers?)
- Misses the separation of concerns (PDS = storage, AppView = aggregation)
- Is correct for a standalone PDS but not for federated network

---

## Missing Endpoints Summary

### High Priority (Core PDS Functionality)
1. `com.atproto.server.createAppPassword` - App-specific passwords
2. `com.atproto.server.listAppPasswords` - List app passwords
3. `com.atproto.server.revokeAppPassword` - Revoke app password
4. `com.atproto.repo.importRepo` - Import repository from CAR
5. `com.atproto.server.confirmEmail` - Email verification
6. `com.atproto.server.requestEmailConfirmation` - Send verification
7. `com.atproto.server.resetPassword` - Password reset
8. `com.atproto.server.requestPasswordReset` - Request reset token

### Medium Priority (Account Management)
9. `com.atproto.server.activateAccount` - Reactivate account
10. `com.atproto.server.deactivateAccount` - Temporarily disable
11. `com.atproto.server.deleteAccount` - Permanent deletion
12. `com.atproto.server.requestAccountDelete` - Request deletion
13. `com.atproto.server.updateEmail` - Email update
14. `com.atproto.server.requestEmailUpdate` - Request email change

### Low Priority (Advanced)
15. `com.atproto.server.getServiceAuth` - Service auth tokens
16. `com.atproto.server.reserveSigningKey` - Key reservation
17. `com.atproto.repo.listMissingBlobs` - Blob sync helper

---

## Recommendations

### Option 1: Keep Current Architecture (Standalone PDS)
**Pros:**
- Everything works for single-user or small PDSs
- No external dependencies (no AppView needed)
- Simpler deployment
- Good for development/testing

**Cons:**
- Not architecturally aligned with Bluesky
- Won't scale to network-wide queries
- Missing official separation of concerns

**Best for:** Personal PDS, development, small communities

### Option 2: Implement Proxy Pattern (Federated PDS)
**Pros:**
- Matches official architecture
- Scales to federated network
- Proper separation: PDS=storage, AppView=aggregation
- Future-proof for network growth

**Cons:**
- Requires AppView deployment
- More complex architecture
- Need to implement read-after-write logic

**Best for:** Production federated network

### Option 3: Hybrid Approach (Recommended)
**Implementation:**
1. ✅ Keep all `com.atproto.*` endpoints as-is (these are correct)
2. ⚠️ Add missing `com.atproto.server.*` endpoints (app passwords, email, etc.)
3. 🔄 Make `app.bsky.*` endpoints **configurable**:
   - If AppView configured → proxy with RAW
   - If no AppView → use local implementation
4. ❌ Remove `app.bsky.notification.*` from PDS (or make it proxy-only)
5. ✅ Keep `app.bsky.graph.*` optional (useful for standalone mode)

**Benefits:**
- Works standalone AND federated
- Correct architecture when AppView available
- Graceful degradation without AppView
- Migration path to full federation

---

## Immediate Action Items

1. **Add Missing Server Endpoints** (High Priority)
   - [ ] `createAppPassword` / `listAppPasswords` / `revokeAppPassword`
   - [ ] Email verification flow
   - [ ] Password reset flow
   - [ ] Account deletion flow

2. **Fix Notification Architecture** (Critical)
   - [ ] Remove notification generation from PDS
   - [ ] Keep only `registerPush` (proxy helper)
   - [ ] Update docs to clarify notifications are AppView responsibility

3. **Document Architecture** (Important)
   - [ ] Update README with architecture decision
   - [ ] Add configuration for AppView URL
   - [ ] Document standalone vs federated modes

4. **Optional: Implement Proxy Pattern** (Future)
   - [ ] Create `ProxyController` module
   - [ ] Implement read-after-write helper
   - [ ] Make app.bsky endpoints configurable
   - [ ] Add AppView client

---

## Conclusion

Our PDS implementation is **functionally correct** but **architecturally different** from the official Bluesky PDS.

**The official PDS is thin** - it:
- Handles core ATProto operations (repo, auth, sync)
- Proxies social features to AppView
- Injects local writes for consistency

**Our PDS is thick** - it:
- Handles everything locally
- Works great for standalone operation
- Missing some official endpoints

**Recommendation:** Add missing `com.atproto.server.*` endpoints, document the architectural difference, and optionally add proxy capability for federation.
