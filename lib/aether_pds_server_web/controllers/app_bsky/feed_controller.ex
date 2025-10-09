defmodule AetherPDSServerWeb.AppBsky.FeedController do
  use AetherPDSServerWeb, :controller

  alias AetherPDSServer.{Accounts, Repositories}

  @doc """
  GET /xrpc/app.bsky.feed.describeFeedGenerator
  """
  def describe_feed_generator(conn, _) do
  end

  @doc """
  GET /xrpc/app.bsky.feed.getActorFeeds
  """
  def get_actor_feeds(conn, _) do
  end

  @doc """
  GET /xrpc/app.bsky.feed.getActorLike
  """
  def get_actor_likes(conn, _) do
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
        {feed_items, next_cursor} = get_author_posts(account.did, limit, cursor, filter)

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
  """
  def get_likes(conn, _) do
  end

  @doc """
  GET /xrpc/app.bsky.feed.getListFeed
  """
  def get_list_feed(conn, _) do
  end

  @doc """
  GET /xrpc/app.bsky.feed.getPostThread
  """
  def get_post_thread(conn, _) do
  end

  @doc """
  GET /xrpc/app.bsky.feed.getPosts
  """
  def get_posts(conn, _) do
  end

  @doc """
  GET /xrpc/app.bsky.feed.getQuotes
  """
  def get_quotes(conn, _) do
  end

  @doc """
  GET /xrpc/app.bsky.feed.getRepostedBy
  """
  def get_reposted_by(conn, _) do
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
  """
  def search_posts(conn, _) do
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
    reposter = get_author_profile(repost_record.repository_did)

    reason = %{
      "$type" => "app.bsky.feed.defs#reasonRepost",
      by: reposter,
      indexedAt: DateTime.utc_now() |> DateTime.to_iso8601()
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
  defp build_reply_context(reply_ref, _current_did) do
    root_uri = get_in(reply_ref, ["root", "uri"])
    parent_uri = get_in(reply_ref, ["parent", "uri"])

    root = fetch_post_view_from_uri(root_uri)
    parent = fetch_post_view_from_uri(parent_uri)

    # Determine grandparentAuthor
    grandparent_author =
      if parent && Map.has_key?(parent, :record) do
        grandparent_reply = Map.get(parent.record, "reply")

        if grandparent_reply do
          grandparent_parent_uri = get_in(grandparent_reply, ["parent", "uri"])

          case parse_at_uri(grandparent_parent_uri) do
            {:ok, {repo_did, _, _}} -> get_author_profile(repo_did)
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
  defp fetch_post_view_from_uri(uri) when is_binary(uri) do
    case parse_at_uri(uri) do
      {:ok, {repo_did, collection, rkey}} ->
        case Repositories.get_record(repo_did, collection, rkey) do
          nil -> nil
          record -> build_post_view_simple(record)
        end

      _ ->
        nil
    end
  end

  defp fetch_post_view_from_uri(_), do: nil

  # Build simple post view (for reply context)
  defp build_post_view_simple(record) do
    author = get_author_profile(record.repository_did)
    uri = "at://#{record.repository_did}/#{record.collection}/#{record.rkey}"

    %{
      "$type" => "app.bsky.feed.defs#postView",
      uri: uri,
      cid: record.cid,
      author: author,
      record: record.value,
      indexedAt: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  # Build full post view
  defp build_post_view(record, _current_did) do
    author = get_author_profile(record.repository_did)
    uri = "at://#{record.repository_did}/#{record.collection}/#{record.rkey}"

    %{
      "$type" => "app.bsky.feed.defs#postView",
      uri: uri,
      cid: record.cid,
      author: author,
      record: record.value,
      indexedAt: DateTime.utc_now() |> DateTime.to_iso8601(),
      replyCount: 0,
      repostCount: 0,
      likeCount: 0,
      quoteCount: 0,
      viewer: %{
        threadMuted: false,
        embeddingDisabled: false
      },
      labels: []
    }
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
  defp get_author_posts(did, limit, cursor, filter) do
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
      |> Enum.map(&build_feed_view_post(&1, did))

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
  defp build_feed_view_post(record, author_did) do
    author = get_author_profile(author_did)
    uri = "at://#{record.repository_did}/#{record.collection}/#{record.rkey}"

    post = %{
      "$type" => "app.bsky.feed.defs#postView",
      uri: uri,
      cid: record.cid,
      author: author,
      record: record.value,
      indexedAt: DateTime.utc_now() |> DateTime.to_iso8601(),
      replyCount: 0,
      repostCount: 0,
      likeCount: 0
    }

    %{
      "$type" => "app.bsky.feed.defs#feedViewPost",
      post: post
    }
  end

  # Get author profile
  defp get_author_profile(did) do
    case Accounts.get_account_by_did(did) do
      nil ->
        %{
          "$type" => "app.bsky.actor.defs#profileViewBasic",
          did: did,
          handle: "unknown.handle"
        }

      account ->
        profile = get_profile_record(did)

        %{
          "$type" => "app.bsky.actor.defs#profileViewBasic",
          did: account.did,
          handle: account.handle,
          displayName: profile["displayName"],
          avatar: profile["avatar"]
        }
        |> Enum.reject(fn {k, v} -> k != :"$type" && is_nil(v) end)
        |> Map.new()
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
end
