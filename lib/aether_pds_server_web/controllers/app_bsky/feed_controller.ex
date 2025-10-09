defmodule AetherPDSServerWeb.AppBsky.FeedController do
  use AetherPDSServerWeb, :controller

  alias AetherPDSServer.{Accounts, Repositories}

  @doc """
  GET /xrpc/app.bsky.feed.describeFeedGenerator

  Get information about a feed generator, including policies and offered feed URIs.
  Parameters:
  - feed: AT URI of the feed generator (required)
  """
  def describe_feed_generator(conn, %{"feed" => feed_uri} = _params) do
    current_did = conn.assigns[:current_did]

    # Parse the feed URI to get the DID and rkey
    case parse_at_uri(feed_uri) do
      {:ok, {did, "app.bsky.feed.generator", rkey}} ->
        # Try to get the feed generator record
        case Repositories.get_record(did, "app.bsky.feed.generator", rkey) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "FeedNotFound", message: "Feed generator not found"})

          record ->
            # Get the creator's profile
            creator = get_author_profile(did, current_did)

            response = %{
              uri: feed_uri,
              cid: record.cid,
              did: record.value["did"] || did,
              creator: creator,
              displayName: record.value["displayName"],
              description: record.value["description"],
              descriptionFacets: record.value["descriptionFacets"],
              avatar: record.value["avatar"],
              likeCount: 0,
              acceptsInteractions: Map.get(record.value, "acceptsInteractions", false),
              labels: [],
              indexedAt: format_timestamp(DateTime.utc_now())
            }

            # Remove nil values
            response =
              response
              |> Enum.reject(fn {_k, v} -> is_nil(v) end)
              |> Map.new()

            json(conn, response)
        end

      _ ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "InvalidRequest", message: "Invalid feed URI format"})
    end
  end

  def describe_feed_generator(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "InvalidRequest", message: "Missing required parameter: feed"})
  end

  @doc """
  GET /xrpc/app.bsky.feed.getActorFeeds

  Get a list of feeds (feed generator records) created by the actor.
  Parameters:
  - actor: AT Identifier (DID or handle) - required
  - limit: Number of items to return (default: 50, max: 100)
  - cursor: Pagination cursor
  """
  def get_actor_feeds(conn, %{"actor" => actor} = params) do
    current_did = conn.assigns[:current_did]
    limit = Map.get(params, "limit", "50") |> parse_integer(50) |> min(100)
    cursor = Map.get(params, "cursor")

    case resolve_actor(actor) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "ActorNotFound", message: "Actor not found"})

      account ->
        # Get feed generator records from the actor
        result =
          Repositories.list_records(account.did, "app.bsky.feed.generator",
            limit: limit + 1,
            cursor: cursor
          )

        generators =
          case result do
            %{records: records} -> records
            _ -> []
          end

        # Paginate
        generators_to_return = Enum.take(generators, limit)

        next_cursor =
          if length(generators) > limit do
            List.last(generators_to_return).rkey
          else
            nil
          end

        # Build feed generator views
        feeds =
          generators_to_return
          |> Enum.map(fn record ->
            uri = "at://#{record.repository_did}/#{record.collection}/#{record.rkey}"
            creator = get_author_profile(record.repository_did, current_did)

            feed_view = %{
              uri: uri,
              cid: record.cid,
              did: record.value["did"] || record.repository_did,
              creator: creator,
              displayName: record.value["displayName"],
              description: record.value["description"],
              descriptionFacets: record.value["descriptionFacets"],
              avatar: record.value["avatar"],
              likeCount: 0,
              acceptsInteractions: Map.get(record.value, "acceptsInteractions", false),
              labels: [],
              indexedAt: format_timestamp(DateTime.utc_now())
            }

            # Remove nil values
            feed_view
            |> Enum.reject(fn {_k, v} -> is_nil(v) end)
            |> Map.new()
          end)

        response = %{cursor: cursor, feeds: feeds}
        response = if next_cursor, do: Map.put(response, :cursor, next_cursor), else: response

        json(conn, response)
    end
  end

  def get_actor_feeds(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "InvalidRequest", message: "Missing required parameter: actor"})
  end

  @doc """
  GET /xrpc/app.bsky.feed.getActorLikes

  Get a list of posts liked by an actor.
  Parameters:
  - actor: AT Identifier (DID or handle) - required
  - limit: Number of items to return (default: 50, max: 100)
  - cursor: Pagination cursor
  """
  def get_actor_likes(conn, %{"actor" => actor} = params) do
    current_did = conn.assigns[:current_did]
    limit = Map.get(params, "limit", "50") |> parse_integer(50) |> min(100)
    cursor = Map.get(params, "cursor")

    case resolve_actor(actor) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "ActorNotFound", message: "Actor not found"})

      account ->
        # Get like records from the actor
        result =
          Repositories.list_records(account.did, "app.bsky.feed.like",
            limit: limit + 1,
            cursor: cursor
          )

        likes =
          case result do
            %{records: records} -> records
            _ -> []
          end

        # Paginate
        likes_to_return = Enum.take(likes, limit)

        next_cursor =
          if length(likes) > limit do
            List.last(likes_to_return).rkey
          else
            nil
          end

        # Build feed views for liked posts
        feed_items =
          likes_to_return
          |> Enum.map(fn like_record ->
            # Get the subject post URI
            subject_uri = get_in(like_record.value, ["subject", "uri"])

            case parse_at_uri(subject_uri) do
              {:ok, {repo_did, collection, rkey}} ->
                case Repositories.get_record(repo_did, collection, rkey) do
                  nil -> nil
                  post_record -> build_feed_view_post(post_record, repo_did, current_did)
                end

              _ ->
                nil
            end
          end)
          |> Enum.reject(&is_nil/1)

        response = %{feed: feed_items}
        response = if next_cursor, do: Map.put(response, :cursor, next_cursor), else: response

        json(conn, response)
    end
  end

  def get_actor_likes(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "InvalidRequest", message: "Missing required parameter: actor"})
  end

  @doc """
  GET /xrpc/app.bsky.feed.getAuthorFeed

  Get a view of an actor's feed (posts and reposts).
  Parameters:
  - actor: AT Identifier (DID or handle) - required
  - limit: Number of items to return (default: 50, max: 100)
  - cursor: Pagination cursor
  - filter: Filter for posts (posts_with_replies, posts_no_replies, posts_with_media, posts_and_author_threads)
  """
  def get_author_feed(conn, %{"actor" => actor} = params) do
    current_did = conn.assigns[:current_did]
    limit = Map.get(params, "limit", "50") |> parse_integer(50) |> min(100)
    cursor = Map.get(params, "cursor")
    filter = Map.get(params, "filter", "posts_with_replies")

    case resolve_actor(actor) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "ActorNotFound", message: "Actor not found"})

      account ->
        # Get posts from the author
        {feed_items, next_cursor} = get_author_posts(account.did, limit, cursor, filter, current_did)

        response = %{feed: feed_items}
        response = if next_cursor, do: Map.put(response, :cursor, next_cursor), else: response

        json(conn, response)
    end
  end

  def get_author_feed(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "InvalidRequest", message: "Missing required parameter: actor"})
  end

  @doc """
  GET /xrpc/app.bsky.feed.getFeedGenerator
  """
  def get_feed_generator(conn, _) do
  end

  @doc """
  GET /xrpc/app.bsky.feed.getFeedGenerators
  """
  def get_feed_generators(conn, _) do
  end

  @doc """
  GET /xrpc/app.bsky.feed.getFeedSkeleton
  """
  def get_feed_skeleton(conn, _) do
  end

  @doc """
  GET /xrpc/app.bsky.feed.getFeed
  """
  def get_feed(conn, _) do
  end

  @doc """
  GET /xrpc/app.bsky.feed.getLikes

  Get likes on a post.
  Parameters:
  - uri: AT URI of the post (required)
  - cid: CID of the post (optional)
  - limit: Number of likes to return (default: 50, max: 100)
  - cursor: Pagination cursor
  """
  def get_likes(conn, %{"uri" => uri} = params) do
    current_did = conn.assigns[:current_did]
    limit = Map.get(params, "limit", "50") |> parse_integer(50) |> min(100)
    cursor = Map.get(params, "cursor")

    # Get all accounts and find likes for this post
    accounts = Accounts.list_accounts()

    likes =
      accounts
      |> Enum.flat_map(fn account ->
        case Repositories.list_records(account.did, "app.bsky.feed.like", limit: 1000) do
          %{records: records} ->
            records
            |> Enum.filter(fn record ->
              subject_uri = get_in(record.value, ["subject", "uri"])
              subject_uri == uri
            end)
            |> Enum.map(fn record ->
              %{
                indexedAt: format_timestamp(DateTime.utc_now()),
                createdAt: Map.get(record.value, "createdAt", format_timestamp(DateTime.utc_now())),
                actor: get_author_profile(account.did, current_did)
              }
            end)

          _ ->
            []
        end
      end)
      |> Enum.sort_by(fn like -> like.createdAt end, :desc)

    # Apply cursor if present
    likes =
      if cursor do
        Enum.drop_while(likes, fn like -> like.createdAt >= cursor end)
      else
        likes
      end

    # Paginate
    likes_to_return = Enum.take(likes, limit)

    next_cursor =
      if length(likes) > limit do
        List.last(likes_to_return).createdAt
      else
        nil
      end

    response = %{
      uri: uri,
      likes: likes_to_return
    }

    response = if next_cursor, do: Map.put(response, :cursor, next_cursor), else: response

    json(conn, response)
  end

  def get_likes(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "InvalidRequest", message: "Missing required parameter: uri"})
  end

  @doc """
  GET /xrpc/app.bsky.feed.getListFeed
  """
  def get_list_feed(conn, _) do
  end

  @doc """
  GET /xrpc/app.bsky.feed.getPostThread

  Get a nested thread of posts.
  Parameters:
  - uri: AT URI of the post (required)
  - depth: How many levels of reply depth to fetch (default: 6, max: 1000)
  - parentHeight: How many levels of parent to fetch (default: 80, max: 1000)
  """
  def get_post_thread(conn, %{"uri" => uri} = params) do
    current_did = conn.assigns[:current_did]
    depth = Map.get(params, "depth", "6") |> parse_integer(6) |> min(1000)
    parent_height = Map.get(params, "parentHeight", "80") |> parse_integer(80) |> min(1000)

    case parse_at_uri(uri) do
      {:ok, {repo_did, collection, rkey}} ->
        case Repositories.get_record(repo_did, collection, rkey) do
          nil ->
            # Return not found thread
            thread = %{
              "$type" => "app.bsky.feed.defs#notFoundPost",
              uri: uri,
              notFound: true
            }

            json(conn, %{thread: thread})

          record ->
            thread = build_thread_view(record, current_did, depth, parent_height)
            json(conn, %{thread: thread})
        end

      {:error, _} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "InvalidRequest", message: "Invalid AT URI format"})
    end
  end

  def get_post_thread(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "InvalidRequest", message: "Missing required parameter: uri"})
  end

  @doc """
  GET /xrpc/app.bsky.feed.getPosts

  Get a view of multiple posts by their URIs.
  Parameters:
  - uris: Array of post URIs (required, max 25)
  """
  def get_posts(conn, %{"uris" => uris} = _params) when is_list(uris) do
    current_did = conn.assigns[:current_did]

    posts =
      uris
      |> Enum.take(25)
      |> Enum.map(fn uri ->
        case parse_at_uri(uri) do
          {:ok, {repo_did, collection, rkey}} ->
            case Repositories.get_record(repo_did, collection, rkey) do
              nil -> nil
              record -> build_post_view(record, current_did)
            end

          _ ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    json(conn, %{posts: posts})
  end

  # Handle single URI (when Phoenix doesn't parse as list)
  def get_posts(conn, %{"uris" => uri}) when is_binary(uri) do
    get_posts(conn, %{"uris" => [uri]})
  end

  # Handle missing uris parameter
  def get_posts(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "InvalidRequest", message: "Missing required parameter: uris"})
  end

  @doc """
  GET /xrpc/app.bsky.feed.getQuotes
  """
  def get_quotes(conn, _) do
  end

  @doc """
  GET /xrpc/app.bsky.feed.getRepostedBy

  Get accounts that reposted a post.
  Parameters:
  - uri: AT URI of the post (required)
  - cid: CID of the post (optional)
  - limit: Number of reposts to return (default: 50, max: 100)
  - cursor: Pagination cursor
  """
  def get_reposted_by(conn, %{"uri" => uri} = params) do
    current_did = conn.assigns[:current_did]
    limit = Map.get(params, "limit", "50") |> parse_integer(50) |> min(100)
    cursor = Map.get(params, "cursor")

    # Get all accounts and find reposts for this post
    accounts = Accounts.list_accounts()

    reposters =
      accounts
      |> Enum.flat_map(fn account ->
        case Repositories.list_records(account.did, "app.bsky.feed.repost", limit: 1000) do
          %{records: records} ->
            records
            |> Enum.filter(fn record ->
              subject_uri = get_in(record.value, ["subject", "uri"])
              subject_uri == uri
            end)
            |> Enum.map(fn record ->
              %{
                indexedAt: format_timestamp(DateTime.utc_now()),
                createdAt: Map.get(record.value, "createdAt", format_timestamp(DateTime.utc_now())),
                actor: get_author_profile(account.did, current_did)
              }
            end)

          _ ->
            []
        end
      end)
      |> Enum.sort_by(fn repost -> repost.createdAt end, :desc)

    # Apply cursor if present
    reposters =
      if cursor do
        Enum.drop_while(reposters, fn repost -> repost.createdAt >= cursor end)
      else
        reposters
      end

    # Paginate
    reposters_to_return = Enum.take(reposters, limit)

    next_cursor =
      if length(reposters) > limit do
        List.last(reposters_to_return).createdAt
      else
        nil
      end

    response = %{
      uri: uri,
      repostedBy: Enum.map(reposters_to_return, fn r -> r.actor end)
    }

    response = if next_cursor, do: Map.put(response, :cursor, next_cursor), else: response

    json(conn, response)
  end

  def get_reposted_by(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "InvalidRequest", message: "Missing required parameter: uri"})
  end

  @doc """
  GET /xrpc/app.bsky.feed.getSuggestedFeeds
  """
  def get_suggested_feeds(conn, _) do
  end

  @doc """
  GET /xrpc/app.bsky.feed.getTimeline

  Get a view of the requesting account's home timeline.
  This is expected to be some form of reverse-chronological feed.

  Parameters:
  - algorithm: Variant 'algorithm' for timeline (optional)
  - limit: Number of items to return (default: 50, max: 100)
  - cursor: Pagination cursor (timestamp-based)

  Requires authentication.
  """
  def get_timeline(conn, params) do
    current_did = conn.assigns[:current_did]

    if is_nil(current_did) do
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "AuthRequired", message: "Authentication required"})
    else
      limit = Map.get(params, "limit", "50") |> parse_integer(50) |> min(100)
      cursor = Map.get(params, "cursor")

      # Get timeline feed items
      {feed_items, next_cursor} = get_timeline_feed(current_did, limit, cursor)

      response = %{feed: feed_items}
      response = if next_cursor, do: Map.put(response, :cursor, next_cursor), else: response

      json(conn, response)
    end
  end

  @doc """
  GET /xrpc/app.bsky.feed.searchPosts

  Search for posts matching a query.
  Parameters:
  - q: Search query (required)
  - limit: Number of results (default: 25, max: 100)
  - cursor: Pagination cursor
  - sort: Sort order ("top" or "latest", default: "latest")
  - since: ISO8601 datetime - only posts after this time
  - until: ISO8601 datetime - only posts before this time
  - mentions: DID - filter to posts mentioning this DID
  - author: DID - filter to posts by this author
  - lang: Language code - filter by language
  - domain: Domain - filter by URL domain
  - url: URL - filter by URL
  """
  def search_posts(conn, %{"q" => query} = params) do
    current_did = conn.assigns[:current_did]
    limit = Map.get(params, "limit", "25") |> parse_integer(25) |> min(100)
    cursor = Map.get(params, "cursor")
    sort = Map.get(params, "sort", "latest")
    author_filter = Map.get(params, "author")

    query_lower = String.downcase(query)

    # Get all accounts and search their posts
    accounts = Accounts.list_accounts()

    # Filter accounts by author if specified
    accounts =
      if author_filter do
        Enum.filter(accounts, fn account -> account.did == author_filter end)
      else
        accounts
      end

    posts =
      accounts
      |> Enum.flat_map(fn account ->
        case Repositories.list_records(account.did, "app.bsky.feed.post", limit: 1000) do
          %{records: records} ->
            records
            |> Enum.filter(fn record ->
              # Search in post text
              text = Map.get(record.value, "text", "")
              String.contains?(String.downcase(text), query_lower)
            end)
            |> Enum.map(fn record ->
              {get_post_timestamp(record), record}
            end)

          _ ->
            []
        end
      end)

    # Sort based on parameter
    posts =
      case sort do
        "top" ->
          # Sort by engagement (likes + reposts + replies)
          Enum.sort_by(posts, fn {_ts, record} ->
            uri = "at://#{record.repository_did}/#{record.collection}/#{record.rkey}"
            {reply_count, repost_count, like_count, _quote_count} = get_post_engagement_counts(uri)
            -(reply_count + repost_count + like_count)
          end)

        _ ->
          # Sort by timestamp (latest first)
          Enum.sort_by(posts, fn {ts, _record} -> ts end, {:desc, DateTime})
      end

    # Apply cursor if present (timestamp-based)
    posts =
      if cursor do
        case DateTime.from_iso8601(cursor) do
          {:ok, cursor_dt, _} ->
            Enum.drop_while(posts, fn {ts, _record} ->
              DateTime.compare(ts, cursor_dt) != :lt
            end)

          _ ->
            posts
        end
      else
        posts
      end

    # Paginate
    posts_to_return = Enum.take(posts, limit)

    next_cursor =
      if length(posts) > limit do
        {last_ts, _} = List.last(posts_to_return)
        format_timestamp(last_ts)
      else
        nil
      end

    # Build feed views
    feed_posts =
      posts_to_return
      |> Enum.map(fn {_ts, record} ->
        build_post_view(record, current_did)
      end)

    response = %{posts: feed_posts}
    response = if next_cursor, do: Map.put(response, :cursor, next_cursor), else: response

    json(conn, response)
  end

  def search_posts(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "InvalidRequest", message: "Missing required parameter: q"})
  end

  @doc """
  /xrpc/app.bsky.feed.sendInteractions
  """
  def send_interactions(conn, _) do
  end

  # --------------
  # Helper Functions
  # --------------

  # Resolve actor by DID or handle
  defp resolve_actor(actor) do
    cond do
      String.starts_with?(actor, "did:") ->
        Accounts.get_account_by_did(actor)

      true ->
        Accounts.get_account_by_handle(actor)
    end
  end

  # Get timeline feed for the current user
  defp get_timeline_feed(current_did, limit, cursor) do
    # Get list of accounts the current user follows
    followed_dids = get_followed_accounts(current_did)

    # Include the current user's own posts
    all_dids = [current_did | followed_dids]

    # Collect posts from all followed accounts
    timeline_items = collect_timeline_items(all_dids, cursor)

    # Sort by timestamp (most recent first)
    sorted_items =
      timeline_items
      |> Enum.sort_by(fn item ->
        case item do
          {:post, record} -> get_post_timestamp(record)
          {:repost, repost_record, _original_post} -> get_post_timestamp(repost_record)
        end
      end, {:desc, DateTime})

    # Paginate
    items_to_return = Enum.take(sorted_items, limit)

    # Determine next cursor from the last item
    next_cursor =
      if length(sorted_items) > limit do
        last_item = List.last(items_to_return)

        case last_item do
          {:post, record} -> get_post_timestamp(record) |> DateTime.to_iso8601()
          {:repost, repost_record, _} -> get_post_timestamp(repost_record) |> DateTime.to_iso8601()
        end
      else
        nil
      end

    # Build feed views
    feed_items =
      items_to_return
      |> Enum.map(&build_timeline_feed_item(&1, current_did))

    {feed_items, next_cursor}
  end

  # Get accounts that the current user follows
  defp get_followed_accounts(did) do
    case Repositories.list_records(did, "app.bsky.graph.follow", limit: 1000) do
      %{records: records} ->
        records
        |> Enum.map(fn record ->
          record.value["subject"]
        end)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  # Collect timeline items (posts and reposts) from all followed accounts
  defp collect_timeline_items(dids, cursor) do
    Enum.flat_map(dids, fn did ->
      # Get posts from this account
      posts =
        case Repositories.list_records(did, "app.bsky.feed.post", limit: 100) do
          %{records: records} -> records
          _ -> []
        end

      # Get reposts from this account
      reposts =
        case Repositories.list_records(did, "app.bsky.feed.repost", limit: 100) do
          %{records: records} -> records
          _ -> []
        end

      # Filter by cursor if present
      posts = filter_by_cursor(posts, cursor)
      reposts = filter_by_cursor(reposts, cursor)

      # Tag posts and reposts
      post_items = Enum.map(posts, fn post -> {:post, post} end)

      repost_items =
        Enum.map(reposts, fn repost ->
          # Fetch the original post
          subject_uri = repost.value["subject"]["uri"]

          case parse_at_uri(subject_uri) do
            {:ok, {repo_did, collection, rkey}} ->
              case Repositories.get_record(repo_did, collection, rkey) do
                nil -> nil
                original_post -> {:repost, repost, original_post}
              end

            _ ->
              nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      post_items ++ repost_items
    end)
  end

  # Filter records by cursor (timestamp)
  defp filter_by_cursor(records, nil), do: records

  defp filter_by_cursor(records, cursor) do
    case DateTime.from_iso8601(cursor) do
      {:ok, cursor_dt, _} ->
        Enum.filter(records, fn record ->
          record_dt = get_post_timestamp(record)
          DateTime.compare(record_dt, cursor_dt) == :lt
        end)

      _ ->
        records
    end
  end

  # Get post timestamp from record
  defp get_post_timestamp(record) do
    # Try to get createdAt from the record value
    case Map.get(record.value, "createdAt") do
      nil ->
        # Fallback to inserted_at if available
        if record.inserted_at do
          DateTime.from_naive!(record.inserted_at, "Etc/UTC")
        else
          DateTime.utc_now()
        end

      created_at_str ->
        case DateTime.from_iso8601(created_at_str) do
          {:ok, dt, _} -> dt
          _ -> DateTime.utc_now()
        end
    end
  end

  # Build timeline feed item (handles both posts and reposts)
  defp build_timeline_feed_item({:post, record}, current_did) do
    post = build_post_view(record, current_did)

    feed_item = %{
      "$type" => "app.bsky.feed.defs#feedViewPost",
      post: post
    }

    # Add reply context if this post is a reply
    feed_item =
      if Map.has_key?(record.value, "reply") do
        case build_reply_context(record.value["reply"], current_did) do
          nil -> feed_item
          reply_context -> Map.put(feed_item, :reply, reply_context)
        end
      else
        feed_item
      end

    feed_item
  end

  defp build_timeline_feed_item({:repost, repost_record, original_post}, current_did) do
    post = build_post_view(original_post, current_did)

    # Build reason (who reposted it)
    reposter = get_author_profile(repost_record.repository_did, current_did)

    reason = %{
      "$type" => "app.bsky.feed.defs#reasonRepost",
      by: reposter,
      indexedAt: format_timestamp(DateTime.utc_now())
    }

    feed_item = %{
      "$type" => "app.bsky.feed.defs#feedViewPost",
      post: post,
      reason: reason
    }

    # Add reply context if the original post is a reply
    feed_item =
      if Map.has_key?(original_post.value, "reply") do
        case build_reply_context(original_post.value["reply"], current_did) do
          nil -> feed_item
          reply_context -> Map.put(feed_item, :reply, reply_context)
        end
      else
        feed_item
      end

    feed_item
  end

  # Build reply context (root, parent, grandparentAuthor)
  defp build_reply_context(reply_ref, current_did) do
    root_uri = get_in(reply_ref, ["root", "uri"])
    parent_uri = get_in(reply_ref, ["parent", "uri"])

    root = fetch_post_view_from_uri(root_uri, current_did)
    parent = fetch_post_view_from_uri(parent_uri, current_did)

    # Determine grandparentAuthor
    grandparent_author =
      if parent && Map.has_key?(parent, :record) do
        grandparent_reply = Map.get(parent.record, "reply")

        if grandparent_reply do
          grandparent_parent_uri = get_in(grandparent_reply, ["parent", "uri"])

          case parse_at_uri(grandparent_parent_uri) do
            {:ok, {repo_did, _, _}} -> get_author_profile(repo_did, current_did)
            _ -> nil
          end
        else
          nil
        end
      else
        nil
      end

    reply_context = %{
      root: root,
      parent: parent
    }

    reply_context =
      if grandparent_author do
        Map.put(reply_context, :grandparentAuthor, grandparent_author)
      else
        reply_context
      end

    # Remove nil values
    reply_context
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> case do
      [] -> nil
      list -> Map.new(list)
    end
  end

  # Fetch post view from AT URI
  defp fetch_post_view_from_uri(uri, current_did \\ nil) when is_binary(uri) do
    case parse_at_uri(uri) do
      {:ok, {repo_did, collection, rkey}} ->
        case Repositories.get_record(repo_did, collection, rkey) do
          nil -> nil
          record -> build_post_view_simple(record, current_did)
        end

      _ ->
        nil
    end
  end

  defp fetch_post_view_from_uri(_, _), do: nil

  # Build simple post view (for reply context)
  defp build_post_view_simple(record, current_did \\ nil) do
    author = get_author_profile(record.repository_did, current_did)
    uri = "at://#{record.repository_did}/#{record.collection}/#{record.rkey}"

    # Get engagement counts
    {reply_count, repost_count, like_count, quote_count} = get_post_engagement_counts(uri)

    # Build viewer state for this post
    viewer = build_post_viewer_state(current_did, uri)

    %{
      "$type" => "app.bsky.feed.defs#postView",
      uri: uri,
      cid: record.cid,
      author: author,
      record: record.value,
      replyCount: reply_count,
      repostCount: repost_count,
      likeCount: like_count,
      quoteCount: quote_count,
      bookmarkCount: 0,
      indexedAt: format_timestamp(DateTime.utc_now()),
      viewer: viewer,
      labels: []
    }
  end

  # Build full post view
  defp build_post_view(record, current_did) do
    author = get_author_profile(record.repository_did, current_did)
    uri = "at://#{record.repository_did}/#{record.collection}/#{record.rkey}"

    # Get engagement counts
    {reply_count, repost_count, like_count, quote_count} = get_post_engagement_counts(uri)

    # Build viewer state for this post
    viewer = build_post_viewer_state(current_did, uri)

    %{
      "$type" => "app.bsky.feed.defs#postView",
      uri: uri,
      cid: record.cid,
      author: author,
      record: record.value,
      replyCount: reply_count,
      repostCount: repost_count,
      likeCount: like_count,
      quoteCount: quote_count,
      bookmarkCount: 0,
      indexedAt: format_timestamp(DateTime.utc_now()),
      viewer: viewer,
      labels: []
    }
  end

  # Build viewer state for a post
  defp build_post_viewer_state(nil, _post_uri) do
    %{
      bookmarked: false,
      threadMuted: false,
      embeddingDisabled: false
    }
  end

  defp build_post_viewer_state(current_did, post_uri) do
    # Check if user has liked this post
    like_uri = check_if_liked(current_did, post_uri)

    # Check if user has reposted this post
    repost_uri = check_if_reposted(current_did, post_uri)

    viewer = %{
      bookmarked: false,
      threadMuted: false,
      embeddingDisabled: false
    }

    viewer = if like_uri, do: Map.put(viewer, :like, like_uri), else: viewer
    viewer = if repost_uri, do: Map.put(viewer, :repost, repost_uri), else: viewer

    viewer
  end

  # Check if user has liked a post, return like record URI if found
  defp check_if_liked(user_did, post_uri) do
    case Repositories.list_records(user_did, "app.bsky.feed.like", limit: 1000) do
      %{records: records} ->
        records
        |> Enum.find(fn record ->
          subject_uri = get_in(record.value, ["subject", "uri"])
          subject_uri == post_uri
        end)
        |> case do
          nil -> nil
          record -> "at://#{record.repository_did}/app.bsky.feed.like/#{record.rkey}"
        end

      _ ->
        nil
    end
  end

  # Check if user has reposted a post, return repost record URI if found
  defp check_if_reposted(user_did, post_uri) do
    case Repositories.list_records(user_did, "app.bsky.feed.repost", limit: 1000) do
      %{records: records} ->
        records
        |> Enum.find(fn record ->
          subject_uri = get_in(record.value, ["subject", "uri"])
          subject_uri == post_uri
        end)
        |> case do
          nil -> nil
          record -> "at://#{record.repository_did}/app.bsky.feed.repost/#{record.rkey}"
        end

      _ ->
        nil
    end
  end

  # Parse AT URI format: at://did:plc:xxx/app.bsky.feed.post/xxx
  defp parse_at_uri(uri) do
    case String.split(uri, "/") do
      ["at:", "", did, collection, rkey] ->
        {:ok, {did, collection, rkey}}

      _ ->
        {:error, :invalid_uri}
    end
  end

  # Get author posts with pagination
  defp get_author_posts(did, limit, cursor, filter, current_did \\ nil) do
    # Get all posts from the author
    result =
      Repositories.list_records(did, "app.bsky.feed.post", limit: limit + 1, cursor: cursor)

    posts =
      case result do
        %{records: records} -> records
        _ -> []
      end

    # Apply filter
    filtered_posts = apply_feed_filter(posts, filter, did)

    # Paginate
    posts_to_return = Enum.take(filtered_posts, limit)

    next_cursor =
      if length(filtered_posts) > limit do
        List.last(posts_to_return).rkey
      else
        nil
      end

    feed_items =
      posts_to_return
      |> Enum.map(&build_feed_view_post(&1, did, current_did))

    {feed_items, next_cursor}
  end

  # Apply feed filter
  defp apply_feed_filter(posts, "posts_no_replies", _did) do
    # Filter out replies
    Enum.filter(posts, fn post ->
      not Map.has_key?(post.value, "reply")
    end)
  end

  defp apply_feed_filter(posts, "posts_with_media", _did) do
    # Filter to only posts with media embeds
    Enum.filter(posts, fn post ->
      has_media_embed?(post.value)
    end)
  end

  defp apply_feed_filter(posts, _filter, _did) do
    # Default: posts_with_replies - return all posts
    posts
  end

  # Check if post has media embed
  defp has_media_embed?(post_value) do
    case Map.get(post_value, "embed") do
      nil ->
        false

      embed ->
        embed_type = Map.get(embed, "$type", "")

        String.contains?(embed_type, "images") or
          String.contains?(embed_type, "video") or
          String.contains?(embed_type, "external")
    end
  end

  # Build feed view post
  defp build_feed_view_post(record, author_did, current_did \\ nil) do
    author = get_author_profile(author_did, current_did)
    uri = "at://#{record.repository_did}/#{record.collection}/#{record.rkey}"

    # Get engagement counts
    {reply_count, repost_count, like_count, quote_count} = get_post_engagement_counts(uri)

    # Build viewer state for this post
    viewer = build_post_viewer_state(current_did, uri)

    post = %{
      "$type" => "app.bsky.feed.defs#postView",
      uri: uri,
      cid: record.cid,
      author: author,
      record: record.value,
      replyCount: reply_count,
      repostCount: repost_count,
      likeCount: like_count,
      quoteCount: quote_count,
      bookmarkCount: 0,
      indexedAt: format_timestamp(DateTime.utc_now()),
      viewer: viewer,
      labels: []
    }

    # Check if post needs threadgate
    post = maybe_add_threadgate(post, record)

    feed_item = %{
      "$type" => "app.bsky.feed.defs#feedViewPost",
      post: post
    }

    # Add reply context if this post is a reply
    feed_item =
      if Map.has_key?(record.value, "reply") do
        case build_reply_context_for_feed(record.value["reply"], current_did) do
          nil -> feed_item
          reply_context -> Map.put(feed_item, :reply, reply_context)
        end
      else
        feed_item
      end

    feed_item
  end

  # Build reply context for feed items (simpler than thread context)
  defp build_reply_context_for_feed(reply_ref, current_did) do
    root_uri = get_in(reply_ref, ["root", "uri"])
    parent_uri = get_in(reply_ref, ["parent", "uri"])

    # Fetch root and parent post views
    root = fetch_post_view_from_uri(root_uri, current_did)
    parent = fetch_post_view_from_uri(parent_uri, current_did)

    if root || parent do
      reply_context = %{}
      reply_context = if root, do: Map.put(reply_context, :root, root), else: reply_context
      reply_context = if parent, do: Map.put(reply_context, :parent, parent), else: reply_context
      reply_context
    else
      nil
    end
  end

  # Maybe add threadgate to post if it exists
  defp maybe_add_threadgate(post, record) do
    # Check if there's a threadgate record for this post
    case Repositories.get_record(
           record.repository_did,
           "app.bsky.feed.threadgate",
           record.rkey
         ) do
      nil ->
        post

      threadgate_record ->
        threadgate = %{
          uri: "at://#{threadgate_record.repository_did}/#{threadgate_record.collection}/#{threadgate_record.rkey}",
          cid: threadgate_record.cid,
          record: threadgate_record.value,
          lists: []
        }

        Map.put(post, :threadgate, threadgate)
    end
  end

  # Get author profile with enhanced fields
  defp get_author_profile(did, current_did \\ nil) do
    case Accounts.get_account_by_did(did) do
      nil ->
        %{
          "$type" => "app.bsky.actor.defs#profileViewBasic",
          did: did,
          handle: "unknown.handle",
          viewer: %{
            muted: false,
            blockedBy: false
          },
          labels: []
        }

      account ->
        profile = get_profile_record(did)

        # Build base profile
        profile_map = %{
          "$type" => "app.bsky.actor.defs#profileViewBasic",
          did: account.did,
          handle: account.handle,
          displayName: profile["displayName"],
          avatar: profile["avatar"]
        }

        # Add createdAt if available from account
        profile_map =
          if account.inserted_at do
            created_at =
              account.inserted_at
              |> DateTime.from_naive!("Etc/UTC")
              |> format_timestamp()

            Map.put(profile_map, :createdAt, created_at)
          else
            profile_map
          end

        # Add associated field (activity subscription and chat)
        profile_map =
          Map.put(profile_map, :associated, %{
            activitySubscription: %{
              allowSubscriptions: false
            }
          })

        # Add verification field (stubbed for now - would query verification records)
        # Real implementation would check for verified domain/handle
        profile_map = Map.put(profile_map, :verification, build_verification_status(did))

        # Add viewer state
        profile_map =
          Map.put(profile_map, :viewer, build_author_viewer_state(current_did, did))

        # Add labels
        profile_map = Map.put(profile_map, :labels, [])

        # Remove nil values except for viewer, labels, associated, and verification
        profile_map
        |> Enum.reject(fn
          {:"$type", _} -> false
          {:viewer, _} -> false
          {:labels, _} -> false
          {:associated, _} -> false
          {:verification, _} -> false
          {_k, v} -> is_nil(v)
        end)
        |> Map.new()
    end
  end

  # Build verification status for an account
  defp build_verification_status(_did) do
    # TODO: Implement actual verification checking
    # For now, return basic unverified status
    %{
      verifications: [],
      verifiedStatus: "none",
      trustedVerifierStatus: "none"
    }
  end

  # Build viewer state for author profile
  defp build_author_viewer_state(nil, _profile_did) do
    %{
      muted: false,
      blockedBy: false
    }
  end

  defp build_author_viewer_state(current_did, profile_did) when current_did == profile_did do
    %{
      muted: false,
      blockedBy: false
    }
  end

  defp build_author_viewer_state(current_did, profile_did) do
    # Check if current user follows this profile
    following_uri = check_if_following(current_did, profile_did)
    followed_by_uri = check_if_following(profile_did, current_did)

    viewer = %{
      muted: false,
      blockedBy: false
    }

    viewer = if following_uri, do: Map.put(viewer, :following, following_uri), else: viewer
    viewer = if followed_by_uri, do: Map.put(viewer, :followedBy, followed_by_uri), else: viewer

    viewer
  end

  # Check if follower_did follows subject_did, return follow record URI if found
  defp check_if_following(follower_did, subject_did) do
    case Repositories.list_records(follower_did, "app.bsky.graph.follow", limit: 1000) do
      %{records: records} ->
        records
        |> Enum.find(fn record ->
          record.value["subject"] == subject_did
        end)
        |> case do
          nil -> nil
          record -> "at://#{record.repository_did}/app.bsky.graph.follow/#{record.rkey}"
        end

      _ ->
        nil
    end
  end

  # Get profile record
  defp get_profile_record(did) do
    case Repositories.get_record(did, "app.bsky.actor.profile", "self") do
      nil -> %{}
      record -> record.value
    end
  end

  # Parse integer with default fallback
  defp parse_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_integer(value, _default) when is_integer(value), do: value
  defp parse_integer(_, default), do: default

  # Format timestamp to ISO8601 with milliseconds (e.g., 2025-10-09T17:15:14.922Z)
  defp format_timestamp(datetime) do
    datetime
    |> DateTime.truncate(:millisecond)
    |> DateTime.to_iso8601()
  end

  # Build nested thread view for get_post_thread
  defp build_thread_view(record, current_did, max_depth, max_parent_height) do
    uri = "at://#{record.repository_did}/#{record.collection}/#{record.rkey}"
    post = build_post_view(record, current_did)

    # Check if this is the root of the thread
    parent_ref = get_in(record.value, ["reply", "parent"])

    # Build parent chain if exists and within height limit
    parent =
      if parent_ref && max_parent_height > 0 do
        parent_uri = parent_ref["uri"]

        case parse_at_uri(parent_uri) do
          {:ok, {repo_did, collection, rkey}} ->
            case Repositories.get_record(repo_did, collection, rkey) do
              nil ->
                %{
                  "$type" => "app.bsky.feed.defs#notFoundPost",
                  uri: parent_uri,
                  notFound: true
                }

              parent_record ->
                build_thread_view(parent_record, current_did, max_depth, max_parent_height - 1)
            end

          _ ->
            %{
              "$type" => "app.bsky.feed.defs#notFoundPost",
              uri: parent_uri,
              notFound: true
            }
        end
      else
        nil
      end

    # Get replies if within depth limit
    replies =
      if max_depth > 0 do
        get_thread_replies(uri, current_did, max_depth)
      else
        []
      end

    # Build thread item
    thread_item = %{
      "$type" => "app.bsky.feed.defs#threadViewPost",
      post: post
    }

    thread_item = if parent, do: Map.put(thread_item, :parent, parent), else: thread_item

    thread_item =
      if length(replies) > 0, do: Map.put(thread_item, :replies, replies), else: thread_item

    thread_item
  end

  # Get replies for a post in a thread
  defp get_thread_replies(post_uri, current_did, max_depth) when max_depth > 0 do
    # Get all accounts and find replies
    accounts = Accounts.list_accounts()

    accounts
    |> Enum.flat_map(fn account ->
      case Repositories.list_records(account.did, "app.bsky.feed.post", limit: 1000) do
        %{records: records} ->
          records
          |> Enum.filter(fn record ->
            parent_uri = get_in(record.value, ["reply", "parent", "uri"])
            parent_uri == post_uri
          end)
          |> Enum.map(fn record ->
            build_thread_view(record, current_did, max_depth - 1, 0)
          end)

        _ ->
          []
      end
    end)
  end

  defp get_thread_replies(_post_uri, _current_did, _max_depth), do: []

  # Get engagement counts for a post
  defp get_post_engagement_counts(post_uri) do
    # Count replies - posts that have this post as parent or root
    reply_count = count_replies_to_post(post_uri)

    # Count reposts - app.bsky.feed.repost records with this post as subject
    repost_count = count_reposts_of_post(post_uri)

    # Count likes - app.bsky.feed.like records with this post as subject
    like_count = count_likes_of_post(post_uri)

    # Count quotes - posts with this post in embed.record
    quote_count = count_quotes_of_post(post_uri)

    {reply_count, repost_count, like_count, quote_count}
  end

  # Count replies to a post
  defp count_replies_to_post(post_uri) do
    # Get all accounts to check their posts
    accounts = Accounts.list_accounts()

    accounts
    |> Enum.map(fn account ->
      case Repositories.list_records(account.did, "app.bsky.feed.post", limit: 1000) do
        %{records: records} ->
          Enum.count(records, fn record ->
            reply_parent = get_in(record.value, ["reply", "parent", "uri"])
            reply_root = get_in(record.value, ["reply", "root", "uri"])
            reply_parent == post_uri || reply_root == post_uri
          end)

        _ ->
          0
      end
    end)
    |> Enum.sum()
  end

  # Count reposts of a post
  defp count_reposts_of_post(post_uri) do
    accounts = Accounts.list_accounts()

    accounts
    |> Enum.map(fn account ->
      case Repositories.list_records(account.did, "app.bsky.feed.repost", limit: 1000) do
        %{records: records} ->
          Enum.count(records, fn record ->
            subject_uri = get_in(record.value, ["subject", "uri"])
            subject_uri == post_uri
          end)

        _ ->
          0
      end
    end)
    |> Enum.sum()
  end

  # Count likes of a post
  defp count_likes_of_post(post_uri) do
    accounts = Accounts.list_accounts()

    accounts
    |> Enum.map(fn account ->
      case Repositories.list_records(account.did, "app.bsky.feed.like", limit: 1000) do
        %{records: records} ->
          Enum.count(records, fn record ->
            subject_uri = get_in(record.value, ["subject", "uri"])
            subject_uri == post_uri
          end)

        _ ->
          0
      end
    end)
    |> Enum.sum()
  end

  # Count quotes of a post (posts that embed this post)
  defp count_quotes_of_post(post_uri) do
    accounts = Accounts.list_accounts()

    accounts
    |> Enum.map(fn account ->
      case Repositories.list_records(account.did, "app.bsky.feed.post", limit: 1000) do
        %{records: records} ->
          Enum.count(records, fn record ->
            # Check if embed.record.uri matches the post_uri
            embed_uri = get_in(record.value, ["embed", "record", "uri"])
            embed_uri == post_uri
          end)

        _ ->
          0
      end
    end)
    |> Enum.sum()
  end
end
