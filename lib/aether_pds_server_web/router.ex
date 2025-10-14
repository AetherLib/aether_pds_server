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

    # OAuth protected resource metadata (tells clients this PDS supports OAuth)
    get "/.well-known/oauth-protected-resource", OAuthController, :protected_resource_metadata

    # OAuth server metadata
    get "/.well-known/oauth-authorization-server", OAuthController, :metadata

    # ATProto DID resolution for handle verification
    get "/.well-known/atproto-did", ComATProto.IdentityController, :well_known_did

    # did:web resolution endpoint
    get "/.well-known/did.json", ComATProto.IdentityController, :well_known_did_json

    # PAR (Pushed Authorization Request) endpoint
    post "/oauth/par", OAuthController, :pushed_authorization_request

    # Token endpoints
    post "/oauth/token", OAuthController, :token
    post "/oauth/revoke", OAuthController, :revoke
  end

  # OAuth UI routes (login and consent pages)
  scope "/", AetherPDSServerWeb do
    pipe_through [:browser]

    live "/", HomeLive, :index
    live "/register", RegisterLive, :index
    # live "/oauth/login", LoginLive, :index
    live "/oauth/authorize/consent", ConsentLive, :index
    get "/oauth/authorize", OAuthController, :authorize
    get "/oauth/login", OAuthController, :login_page
    post "/oauth/login", OAuthController, :login
    post "/oauth/authorize/consent", OAuthController, :consent
  end

  # ============================================================================
  # PUBLIC ENDPOINTS (No Authentication Required)
  # ============================================================================

  scope "/xrpc", AetherPDSServerWeb do
    pipe_through :api

    # ------------------------------------------------------------------------
    # 🔄 APPVIEW SCOPE - SHOULD PROXY WITH READ-AFTER-WRITE
    # These endpoints are implemented locally but should be proxied to AppView
    # in production with read-after-write (RAW) pattern for federation.
    # See: https://github.com/bluesky-social/atproto/tree/main/packages/pds/src/api/app/bsky
    # TODO: Extract to AppView + implement RAW proxy pattern
    # ------------------------------------------------------------------------
    # get "/app.bsky.actor.getProfile", AppBsky.ActorController, :get_profile
    # get "/app.bsky.actor.getProfiles", AppBsky.ActorController, :get_profiles
    # get "/app.bsky.actor.searchActors", AppBsky.ActorController, :search_actors
    # get "/app.bsky.actor.searchActorsTypeahead", AppBsky.ActorController, :search_actors_typeahead
    # get "/app.bsky.actor.getSuggestions", AppBsky.ActorController, :get_suggestions
    # get "/app.bsky.labeler.getServices", AppBsky.LabelerController, :get_services
    # get "/app.bsky.feed.getActorFeeds", AppBsky.FeedController, :get_actor_feeds
    # get "/app.bsky.feed.getActorLikes", AppBsky.FeedController, :get_actor_likes
    # get "/app.bsky.feed.getAuthorFeed", AppBsky.FeedController, :get_author_feed
    # get "/app.bsky.feed.describeFeedGenerator", AppBsky.FeedController, :describe_feed_generator
    # get "/app.bsky.feed.getFeed", AppBsky.FeedController, :get_feed
    # get "/app.bsky.feed.getFeedGenerator", AppBsky.FeedController, :get_feed_generator
    # get "/app.bsky.feed.getFeedGenerators", AppBsky.FeedController, :get_feed_generators
    # get "/app.bsky.feed.getFeedSkeleton", AppBsky.FeedController, :get_feed_skeleton
    # get "/app.bsky.feed.getLikes", AppBsky.FeedController, :get_likes
    # get "/app.bsky.feed.getListFeed", AppBsky.FeedController, :get_list_feed
    # get "/app.bsky.feed.getPosts", AppBsky.FeedController, :get_posts
    # get "/app.bsky.feed.getPostThread", AppBsky.FeedController, :get_post_thread
    # get "/app.bsky.feed.getQuotes", AppBsky.FeedController, :get_quotes
    # get "/app.bsky.feed.getRepostedBy", AppBsky.FeedController, :get_reposted_by
    # get "/app.bsky.feed.getSuggestedFeeds", AppBsky.FeedController, :get_suggested_feeds
    # get "/app.bsky.feed.searchPosts", AppBsky.FeedController, :search_posts
    # post "/app.bsky.feed.sendInteractions", AppBsky.FeedController, :send_interactions
    # get "/app.bsky.graph.getFollowers", AppBsky.GraphController, :get_followers
    # get "/app.bsky.graph.getFollows", AppBsky.GraphController, :get_follows
    # get "/app.bsky.unspecced.getConfig", AppBsky.UnspeccedController, :get_config
    # get "/app.bsky.unspecced.getPostThreadV2", AppBsky.UnspeccedController, :get_post_thread_v2

    get "/com.atproto.server.describeServer", ComATProto.ServerController, :describe_server
    post "/com.atproto.server.createAccount", ComATProto.ServerController, :create_account
    post "/com.atproto.server.createSession", ComATProto.ServerController, :create_session
    post "/com.atproto.server.refreshSession", ComATProto.ServerController, :refresh_session

    # TODO: Missing official PDS endpoints (see PDS_COMPARISON.md):
    # - com.atproto.server.confirmEmail (email-related, skipped)
    # - com.atproto.server.requestEmailConfirmation (email-related, skipped)
    # - com.atproto.server.resetPassword (email-related, skipped)
    # - com.atproto.server.requestPasswordReset (email-related, skipped)
    # - com.atproto.server.updateEmail (email-related, skipped)
    # - com.atproto.server.requestEmailUpdate (email-related, skipped)

    get "/com.atproto.repo.describeRepo", ComATProto.RepoController, :describe_repo
    get "/com.atproto.repo.getRecord", ComATProto.RepoController, :get_record
    get "/com.atproto.repo.listRecords", ComATProto.RepoController, :list_records
    get "/com.atproto.repo.listMissingBlobs", ComATProto.RepoController, :list_missing_blobs

    get "/com.atproto.sync.getRepo", ComATProto.SyncController, :get_repo
    get "/com.atproto.sync.getLatestCommit", ComATProto.SyncController, :get_latest_commit
    get "/com.atproto.sync.getRecord", ComATProto.SyncController, :get_record
    get "/com.atproto.sync.getBlocks", ComATProto.SyncController, :get_blocks
    get "/com.atproto.sync.getBlob", ComATProto.SyncController, :get_blob
    get "/com.atproto.sync.listBlobs", ComATProto.SyncController, :list_blobs

    get "/com.atproto.identity.resolveHandle", ComATProto.IdentityController, :resolve_handle
    get "/com.atproto.identity.resolveDid", ComATProto.IdentityController, :resolve_did
  end

  # ============================================================================
  # AUTHENTICATED ENDPOINTS (Requires Valid Session Token)
  # ============================================================================

  scope "/xrpc", AetherPDSServerWeb do
    pipe_through [:api, :authenticated]

    ## ------------ APP VIEW Routes
    # get "/app.bsky.actor.getPreferences", AppBsky.ActorController, :get_preferences
    # post "/app.bsky.actor.putPreferences", AppBsky.ActorController, :put_preferences
    # get "/app.bsky.feed.getTimeline", AppBsky.FeedController, :get_timeline
    # get "/app.bsky.graph.getBlocks", AppBsky.GraphController, :get_blocks
    # get "/app.bsky.graph.getMutes", AppBsky.GraphController, :get_mutes
    # get "/app.bsky.graph.getRelationships", AppBsky.GraphController, :get_relationships
    # post "/app.bsky.graph.muteActor", AppBsky.GraphController, :mute_actor
    # post "/app.bsky.graph.unmuteActor", AppBsky.GraphController, :unmute_actor
    # post "/app.bsky.graph.muteThread", AppBsky.GraphController, :mute_thread
    # post "/app.bsky.graph.unmuteThread", AppBsky.GraphController, :unmute_thread
    # get "/app.bsky.notification.getUnreadCount", AppBsky.NotificationController, :get_unread_count
    # get "/app.bsky.notification.listNotifications", AppBsky.NotificationController, :list_notifications
    # post "/app.bsky.notification.updateSeen", AppBsky.NotificationController, :update_seen
    ## ------------ APP VIEW Routes
    #
    #
    get "/com.atproto.server.getSession", ComATProto.ServerController, :get_session
    post "/com.atproto.server.deleteSession", ComATProto.ServerController, :delete_session

    post "/com.atproto.server.createAppPassword",
         ComATProto.ServerController,
         :create_app_password

    get "/com.atproto.server.listAppPasswords", ComATProto.ServerController, :list_app_passwords

    post "/com.atproto.server.revokeAppPassword",
         ComATProto.ServerController,
         :revoke_app_password

    post "/com.atproto.server.deactivateAccount", ComATProto.ServerController, :deactivate_account
    post "/com.atproto.server.activateAccount", ComATProto.ServerController, :activate_account
    post "/com.atproto.server.deleteAccount", ComATProto.ServerController, :delete_account

    post "/com.atproto.server.requestAccountDelete",
         ComATProto.ServerController,
         :request_account_delete

    get "/com.atproto.server.getServiceAuth", ComATProto.ServerController, :get_service_auth

    post "/com.atproto.server.reserveSigningKey",
         ComATProto.ServerController,
         :reserve_signing_key

    post "/com.atproto.server.rotateSigningKey",
         ComATProto.ServerController,
         :rotate_signing_key

    post "/com.atproto.repo.applyWrites", ComATProto.RepoController, :apply_writes
    post "/com.atproto.repo.createRecord", ComATProto.RepoController, :create_record
    post "/com.atproto.repo.putRecord", ComATProto.RepoController, :put_record
    post "/com.atproto.repo.deleteRecord", ComATProto.RepoController, :delete_record
    post "/com.atproto.repo.importRepo", ComATProto.RepoController, :import_repo
    post "/com.atproto.repo.uploadBlob", ComATProto.BlobController, :upload_blob
  end

  scope "/xrpc", AetherPDSServerWeb do
    pipe_through [:api, :authenticated, :admin]
    post "/com.atproto.sync.notifyOfUpdate", ComATProto.SyncController, :notify_of_update
    post "/com.atproto.sync.requestCrawl", ComATProto.SyncController, :request_crawl
  end

  scope "/", AetherPDSServerWeb do
    pipe_through :api

    get "/_health", HealthController, :index
    get "/xrpc/_health", HealthController, :index
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
