defmodule AetherPDSServerWeb.Router do
  use AetherPDSServerWeb, :router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AetherPDSServerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :authenticated do
    plug AetherPDSServerWeb.Plugs.RequireAuth
  end

  pipeline :admin do
    plug AetherPDSServerWeb.Plugs.RequireAdmin
  end

  # ============================================================================
  # OAuth Endpoints (Public)
  # ============================================================================

  scope "/", AetherPDSServerWeb do
    pipe_through :api

    # OAuth server metadata
    get "/.well-known/oauth-authorization-server", OAuthController, :metadata

    # Token endpoints
    post "/oauth/token", OAuthController, :token
    post "/oauth/revoke", OAuthController, :revoke
  end

  # ============================================================================
  # PUBLIC ENDPOINTS (No Authentication Required)
  # ============================================================================

  scope "/xrpc", AetherPDSServerWeb do
    pipe_through :api

    # App Bsky Actor - Public
    get "/app.bsky.actor.getProfile", AppBsky.ActorController, :get_profile
    get "/app.bsky.actor.getProfiles", AppBsky.ActorController, :get_profiles
    get "/app.bsky.actor.searchActors", AppBsky.ActorController, :search_actors
    get "/app.bsky.actor.searchActorsTypeahead", AppBsky.ActorController, :search_actors_typeahead
    get "/app.bsky.actor.getSuggestions", AppBsky.ActorController, :get_suggestions

    # App Bsky Feed - Public
    get "/app.bsky.feed.getAuthorFeed", AppBsky.FeedController, :get_author_feed

    # App Bsky Unspecced - Public
    get "/app.bsky.unspecced.getConfig", AppBsky.UnspeccedController, :get_config
    get "/app.bsky.unspecced.getPostThreadV2", AppBsky.UnspeccedController, :get_post_thread_v2

    # Server Description
    get "/com.atproto.server.describeServer", ComATProto.ServerController, :describe_server

    # Account Creation and Login (Public)
    post "/com.atproto.server.createAccount", ComATProto.ServerController, :create_account
    post "/com.atproto.server.createSession", ComATProto.ServerController, :create_session
    post "/com.atproto.server.refreshSession", ComATProto.ServerController, :refresh_session

    # Repository - Public Reads
    get "/com.atproto.repo.describeRepo", ComATProto.RepoController, :describe_repo
    get "/com.atproto.repo.getRecord", ComATProto.RepoController, :get_record
    get "/com.atproto.repo.listRecords", ComATProto.RepoController, :list_records

    # Sync Protocol - Public (needed for federation)
    get "/com.atproto.sync.getRepo", ComATProto.SyncController, :get_repo
    get "/com.atproto.sync.getLatestCommit", ComATProto.SyncController, :get_latest_commit
    get "/com.atproto.sync.getRecord", ComATProto.SyncController, :get_record
    get "/com.atproto.sync.getBlocks", ComATProto.SyncController, :get_blocks
    get "/com.atproto.sync.getBlob", ComATProto.SyncController, :get_blob
    get "/com.atproto.sync.listBlobs", ComATProto.SyncController, :list_blobs

    # Identity Resolution - Public
    get "/com.atproto.identity.resolveHandle", ComATProto.IdentityController, :resolve_handle
    get "/com.atproto.identity.resolveDid", ComATProto.IdentityController, :resolve_did
  end

  # ============================================================================
  # AUTHENTICATED ENDPOINTS (Requires Valid Session Token)
  # ============================================================================

  scope "/xrpc", AetherPDSServerWeb do
    pipe_through [:api, :authenticated]

    # App Bsky Actor - Authenticated
    get "/app.bsky.actor.getPreferences", AppBsky.ActorController, :get_preferences
    post "/app.bsky.actor.putPreferences", AppBsky.ActorController, :put_preferences

    # App Bsky Feed - Authenticated
    get "/app.bsky.feed.getTimeline", AppBsky.FeedController, :get_timeline

    # Session Management
    get "/com.atproto.server.getSession", ComATProto.ServerController, :get_session
    post "/com.atproto.server.deleteSession", ComATProto.ServerController, :delete_session

    # Repository - Writes (must own the repo)
    post "/com.atproto.repo.applyWrites", ComATProto.RepoController, :apply_writes
    post "/com.atproto.repo.createRecord", ComATProto.RepoController, :create_record
    post "/com.atproto.repo.putRecord", ComATProto.RepoController, :put_record
    post "/com.atproto.repo.deleteRecord", ComATProto.RepoController, :delete_record

    # Blob Operations (must own the repo)
    post "/com.atproto.repo.uploadBlob", ComATProto.BlobController, :upload_blob
  end

  # ============================================================================
  # ADMIN ENDPOINTS (Requires Admin Privileges)
  # ============================================================================

  scope "/xrpc", AetherPDSServerWeb do
    pipe_through [:api, :authenticated, :admin]

    # Sync Administration
    post "/com.atproto.sync.notifyOfUpdate", ComATProto.SyncController, :notify_of_update
    post "/com.atproto.sync.requestCrawl", ComATProto.SyncController, :request_crawl
  end

  # ============================================================================
  # HEALTH CHECK (Public)
  # ============================================================================

  scope "/", AetherPDSServerWeb do
    pipe_through :api

    get "/_health", HealthController, :index
    get "/xrpc/_health", HealthController, :index
  end

  # ============================================================================
  # UI PAGES (LiveView)
  # ============================================================================

  scope "/", AetherPDSServerWeb do
    pipe_through [:browser]

    live "/", HomeLive, :index
    live "/register", RegisterLive, :index
    live "/oauth/login", LoginLive, :index
    live "/oauth/authorize/consent", ConsentLive, :index
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:aether_pds_server, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      live_dashboard "/dashboard", metrics: AetherPDSServerWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
