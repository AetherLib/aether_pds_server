defmodule AetherPDSServerWeb.Router do
  use AetherPDSServerWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :authenticated do
    plug AetherPDSServerWeb.Plugs.RequireAuth
    # This plug will verify JWT tokens and load the user/DID
  end

  pipeline :admin do
    plug AetherPDSServerWeb.Plugs.RequireAdmin
    # Admin-only operations
  end

  # ============================================================================
  # PUBLIC ENDPOINTS (No Authentication Required)
  # ============================================================================

  scope "/xrpc", AetherPDSServerWeb do
    pipe_through :api

    # Account/Session Management (public - needed to create accounts and login)
    post "/com.atproto.server.createAccount", ServerController, :create_account
    post "/com.atproto.server.createSession", ServerController, :create_session
    post "/com.atproto.server.refreshSession", ServerController, :refresh_session
    get "/com.atproto.server.describeServer", ServerController, :describe_server

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
    get "/com.atproto.sync.getHead", SyncController, :get_head
    get "/com.atproto.sync.getCheckout", SyncController, :get_checkout

    # Events/Firehose - Public (AppViews need access)
    # WebSocket
    get "/com.atproto.sync.subscribeRepos", SyncController, :subscribe_repos
    get "/com.atproto.sync.listRepos", SyncController, :list_repos

    # Identity Resolution - Public
    get "/com.atproto.identity.resolveHandle", IdentityController, :resolve_handle
  end

  # ============================================================================
  # AUTHENTICATED ENDPOINTS (Requires Valid Session Token)
  # ============================================================================

  scope "/xrpc", AetherPDSServerWeb do
    pipe_through [:api, :authenticated]

    # Session Management (authenticated)
    get "/com.atproto.server.getSession", ServerController, :get_session
    post "/com.atproto.server.deleteSession", ServerController, :delete_session

    # Repository - Writes (must own the repo)
    post "/com.atproto.repo.createRecord", RepoController, :create_record
    post "/com.atproto.repo.putRecord", RepoController, :put_record
    post "/com.atproto.repo.deleteRecord", RepoController, :delete_record
    # Batch operations
    post "/com.atproto.repo.applyWrites", RepoController, :apply_writes

    # Blob Operations (must own the repo)
    post "/com.atproto.repo.uploadBlob", BlobController, :upload_blob

    # Account Management (acting on own account)
    post "/com.atproto.server.updateHandle", ServerController, :update_handle
    post "/com.atproto.server.requestPasswordReset", ServerController, :request_password_reset
    post "/com.atproto.server.resetPassword", ServerController, :reset_password
    post "/com.atproto.server.requestEmailUpdate", ServerController, :request_email_update
    post "/com.atproto.server.updateEmail", ServerController, :update_email

    post "/com.atproto.server.requestEmailConfirmation",
         ServerController,
         :request_email_confirmation

    post "/com.atproto.server.confirmEmail", ServerController, :confirm_email

    # Identity Management
    post "/com.atproto.identity.updateHandle", IdentityController, :update_handle
  end

  # ============================================================================
  # ADMIN ENDPOINTS (Requires Admin Privileges)
  # ============================================================================

  scope "/xrpc", AetherPDSServerWeb do
    pipe_through [:api, :authenticated, :admin]

    # Server Administration
    post "/com.atproto.server.createInviteCode", ServerController, :create_invite_code
    post "/com.atproto.server.createInviteCodes", ServerController, :create_invite_codes
    get "/com.atproto.server.getAccountInviteCodes", ServerController, :get_account_invite_codes

    # Moderation/Admin
    post "/com.atproto.admin.deleteAccount", AdminController, :delete_account
    post "/com.atproto.admin.disableAccount", AdminController, :disable_account
    post "/com.atproto.admin.enableAccount", AdminController, :enable_account
    get "/com.atproto.admin.getAccountInfo", AdminController, :get_account_info
    get "/com.atproto.admin.getAccountInfos", AdminController, :get_account_infos
    post "/com.atproto.admin.updateAccountEmail", AdminController, :update_account_email
    post "/com.atproto.admin.updateAccountHandle", AdminController, :update_account_handle

    # Sync Administration
    post "/com.atproto.sync.notifyOfUpdate", SyncController, :notify_of_update
    post "/com.atproto.sync.requestCrawl", SyncController, :request_crawl
  end

  # ============================================================================
  # HEALTH CHECK / STATUS (Public)
  # ============================================================================

  scope "/", AetherPDSServerWeb do
    pipe_through :api

    get "/_health", HealthController, :index
    get "/xrpc/_health", HealthController, :index
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:aether_pds_server, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      live_dashboard "/dashboard", metrics: AetherPDSServerWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
