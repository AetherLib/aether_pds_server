defmodule AetherPDSServerWeb.Router do
  use AetherPDSServerWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", AetherPDSServerWeb do
    pipe_through :api
  end

  scope "/xrpc", AetherPDSServerWeb do
    # Public endpoints (no auth required)
    get "/com.atproto.sync.getRepo", RepositoriesController, :get_repo
    get "/com.atproto.sync.getLatestCommit", RepositoriesController, :get_latest_commit
    get "/com.atproto.sync.getRecord", RepositoriesController, :get_record_sync
    get "/com.atproto.sync.getBlocks", RepositoriesController, :get_blocks
    get "/com.atproto.sync.getBlob", RepositoriesController, :get_blob
    get "/com.atproto.sync.listBlobs", RepositoriesController, :list_blobs
    get "/com.atproto.sync.getEvents", RepositoriesController, :get_events
    get "/com.atproto.sync.getCurrentSeq", RepositoriesController, :get_current_seq
    get "/com.atproto.repo.describeRepo", RepositoriesController, :describe_repo
    get "/com.atproto.repo.getRecord", RepositoriesController, :get_record
    get "/com.atproto.repo.listRecords", RepositoriesController, :list_records
  end

  scope "/xrpc", AetherPDSServerWeb do
    # Authenticated endpoints
    post "/com.atproto.repo.createRepo", RepositoriesController, :create_repo
    post "/com.atproto.repo.createRecord", RepositoriesController, :create_record
    post "/com.atproto.repo.putRecord", RepositoriesController, :put_record
    post "/com.atproto.repo.deleteRecord", RepositoriesController, :delete_record
    post "/com.atproto.repo.uploadBlob", RepositoriesController, :upload_blob
    post "/com.atproto.repo.importBlob", RepositoriesController, :import_blob
    post "/com.atproto.repo.linkBlob", RepositoriesController, :link_blob
    post "/com.atproto.repo.unlinkBlob", RepositoriesController, :unlink_blob
  end

  scope "/xrpc", AetherPDSServerWeb do
    # Admin endpoints
    post "/com.atproto.sync.notifyOfUpdate", RepositoriesController, :notify_of_update
    post "/com.atproto.sync.requestCrawl", RepositoriesController, :request_crawl
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
