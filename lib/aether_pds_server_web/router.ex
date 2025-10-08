defmodule AetherPDSServerWeb.Router do
  use AetherPDSServerWeb, :router
  import Phoenix.LiveView.Router

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

    get "/app.bsky.actor.getProfile", Bsky.ActorController, :get_profile

    # Server Description
    get "/com.atproto.server.describeServer", ServerController, :describe_server

    # Account Creation and Login (Public)
    post "/com.atproto.server.createAccount", ServerController, :create_account
    post "/com.atproto.server.createSession", ServerController, :create_session
    post "/com.atproto.server.refreshSession", ServerController, :refresh_session

    # Repository - Public Reads
    get "/com.atproto.repo.describeRepo", RepoController, :describe_repo
    get "/com.atproto.repo.getRecord", RepoController, :get_record
    get "/com.atproto.repo.listRecords", RepoController, :list_records

    # Sync Protocol - Public (needed for federation)
    get "/com.atproto.sync.getRepo", SyncController, :get_repo
    get "/com.atproto.sync.getLatestCommit", SyncController, :get_latest_commit
    get "/com.atproto.sync.getRecord", SyncController, :get_record
    get "/com.atproto.sync.getBlocks", SyncController, :get_blocks
    get "/com.atproto.sync.getBlob", SyncController, :get_blob
    get "/com.atproto.sync.listBlobs", SyncController, :list_blobs

    # Identity Resolution - Public
    get "/com.atproto.identity.resolveHandle", IdentityController, :resolve_handle
    get "/com.atproto.identity.resolveDid", IdentityController, :resolve_did
  end

  # ============================================================================
  # AUTHENTICATED ENDPOINTS (Requires Valid Session Token)
  # ============================================================================

  scope "/xrpc", AetherPDSServerWeb do
    pipe_through [:api, :authenticated]

    # Session Management
    get "/com.atproto.server.getSession", ServerController, :get_session
    post "/com.atproto.server.deleteSession", ServerController, :delete_session

    # Repository - Writes (must own the repo)
    post "/com.atproto.repo.applyWrites", RepoController, :apply_writes
    post "/com.atproto.repo.createRecord", RepoController, :create_record
    post "/com.atproto.repo.putRecord", RepoController, :put_record
    post "/com.atproto.repo.deleteRecord", RepoController, :delete_record

    # Blob Operations (must own the repo)
    post "/com.atproto.repo.uploadBlob", BlobController, :upload_blob
  end

  # ============================================================================
  # ADMIN ENDPOINTS (Requires Admin Privileges)
  # ============================================================================

  scope "/xrpc", AetherPDSServerWeb do
    pipe_through [:api, :authenticated, :admin]

    # Sync Administration
    post "/com.atproto.sync.notifyOfUpdate", SyncController, :notify_of_update
    post "/com.atproto.sync.requestCrawl", SyncController, :request_crawl
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

  # Browser pipeline for UI pages
  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AetherPDSServerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
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
