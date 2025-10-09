# CLAUDE.md
This is a web application written using the Phoenix web framework.

## Project guidelines

- Use `mix precommit` alias when you are done with all changes and fix any pending issues
- Use the already included and available `:req` (`Req`) library for HTTP requests, **avoid** `:httpoison`, `:tesla`, and `:httpc`. Req is included by default and is the preferred HTTP client for Phoenix apps

### Phoenix v1.8 guidelines

- **Always** begin your LiveView templates with `<Layouts.app flash={@flash} ...>` which wraps all inner content
- The `MyAppWeb.Layouts` module is aliased in the `my_app_web.ex` file, so you can use it without needing to alias it again
- Anytime you run into errors with no `current_scope` assign:
  - You failed to follow the Authenticated Routes guidelines, or you failed to pass `current_scope` to `<Layouts.app>`
  - **Always** fix the `current_scope` error by moving your routes to the proper `live_session` and ensure you pass `current_scope` as needed
- Phoenix v1.8 moved the `<.flash_group>` component to the `Layouts` module. You are **forbidden** from calling `<.flash_group>` outside of the `layouts.ex` module
- Out of the box, `core_components.ex` imports an `<.icon name="hero-x-mark" class="w-5 h-5"/>` component for for hero icons. **Always** use the `<.icon>` component for icons, **never** use `Heroicons` modules or similar
- **Always** use the imported `<.input>` component for form inputs from `core_components.ex` when available. `<.input>` is imported and using it will will save steps and prevent errors
- If you override the default input classes (`<.input class="myclass px-2 py-1 rounded-lg">)`) class with your own values, no default classes are inherited, so your
custom classes must fully style the input


<!-- usage-rules-start -->

<!-- phoenix:elixir-start -->
## Elixir guidelines

- Elixir lists **do not support index based access via the access syntax**

  **Never do this (invalid)**:

      i = 0
      mylist = ["blue", "green"]
      mylist[i]

  Instead, **always** use `Enum.at`, pattern matching, or `List` for index based list access, ie:

      i = 0
      mylist = ["blue", "green"]
      Enum.at(mylist, i)

- Elixir variables are immutable, but can be rebound, so for block expressions like `if`, `case`, `cond`, etc
  you *must* bind the result of the expression to a variable if you want to use it and you CANNOT rebind the result inside the expression, ie:

      # INVALID: we are rebinding inside the `if` and the result never gets assigned
      if connected?(socket) do
        socket = assign(socket, :val, val)
      end

      # VALID: we rebind the result of the `if` to a new variable
      socket =
        if connected?(socket) do
          assign(socket, :val, val)
        end

- **Never** nest multiple modules in the same file as it can cause cyclic dependencies and compilation errors
- **Never** use map access syntax (`changeset[:field]`) on structs as they do not implement the Access behaviour by default. For regular structs, you **must** access the fields directly, such as `my_struct.field` or use higher level APIs that are available on the struct if they exist, `Ecto.Changeset.get_field/2` for changesets
- Elixir's standard library has everything necessary for date and time manipulation. Familiarize yourself with the common `Time`, `Date`, `DateTime`, and `Calendar` interfaces by accessing their documentation as necessary. **Never** install additional dependencies unless asked or for date/time parsing (which you can use the `date_time_parser` package)
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Predicate function names should not start with `is_` and should end in a question mark. Names like `is_thing` should be reserved for guards
- Elixir's builtin OTP primitives like `DynamicSupervisor` and `Registry`, require names in the child spec, such as `{DynamicSupervisor, name: MyApp.MyDynamicSup}`, then you can use `DynamicSupervisor.start_child(MyApp.MyDynamicSup, child_spec)`
- Use `Task.async_stream(collection, callback, options)` for concurrent enumeration with back-pressure. The majority of times you will want to pass `timeout: :infinity` as option

## Mix guidelines

- Read the docs and options before using tasks (by using `mix help task_name`)
- To debug test failures, run tests in a specific file with `mix test test/my_test.exs` or run all previously failed tests with `mix test --failed`
- `mix deps.clean --all` is **almost never needed**. **Avoid** using it unless you have good reason
<!-- phoenix:elixir-end -->

<!-- phoenix:phoenix-start -->
## Phoenix guidelines

- Remember Phoenix router `scope` blocks include an optional alias which is prefixed for all routes within the scope. **Always** be mindful of this when creating routes within a scope to avoid duplicate module prefixes.

- You **never** need to create your own `alias` for route definitions! The `scope` provides the alias, ie:

      scope "/admin", AppWeb.Admin do
        pipe_through :browser

        live "/users", UserLive, :index
      end

  the UserLive route would point to the `AppWeb.Admin.UserLive` module

- `Phoenix.View` no longer is needed or included with Phoenix, don't use it
<!-- phoenix:phoenix-end -->

<!-- phoenix:ecto-start -->
## Ecto Guidelines

- **Always** preload Ecto associations in queries when they'll be accessed in templates, ie a message that needs to reference the `message.user.email`
- Remember `import Ecto.Query` and other supporting modules when you write `seeds.exs`
- `Ecto.Schema` fields always use the `:string` type, even for `:text`, columns, ie: `field :name, :string`
- `Ecto.Changeset.validate_number/2` **DOES NOT SUPPORT the `:allow_nil` option**. By default, Ecto validations only run if a change for the given field exists and the change value is not nil, so such as option is never needed
- You **must** use `Ecto.Changeset.get_field(changeset, :field)` to access changeset fields
- Fields which are set programatically, such as `user_id`, must not be listed in `cast` calls or similar for security purposes. Instead they must be explicitly set when creating the struct
<!-- phoenix:ecto-end -->

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
