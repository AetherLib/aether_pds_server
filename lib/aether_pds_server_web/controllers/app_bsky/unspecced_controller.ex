defmodule AetherPDSServerWeb.AppBsky.UnspeccedController do
  use AetherPDSServerWeb, :controller

  alias AetherPDSServer.{Repositories, Accounts}

  @doc """
  GET /xrpc/app.bsky.unspecced.getConfig

  Get server configuration for the Bluesky app.
  Returns various feature flags and live stream configurations.
  """
  def get_config(conn, _params) do
    config = %{
      # Email verification requirement for new signups
      checkEmailConfirmed: false,

      # Topics/hashtags feature enabled
      topicsEnabled: false,

      # Live stream configurations (empty by default)
      # This would list DIDs of users who are live streaming with their associated domains
      liveNow: []
    }

    json(conn, config)
  end

  @doc """
  GET /xrpc/app.bsky.unspecced.getPostThreadV2

  Get a thread of posts, version 2 (unspecced API).
  Returns a flat array of thread items with depth indicators.

  Parameters:
  - anchor: AT URI of the post (required)
  - above: boolean - whether to fetch parent posts (default: true)
  - below: number - depth of replies to fetch (default: 0)
  - branchingFactor: number - how many sibling replies to include (default: 1)
  """
  def get_post_thread_v2(conn, %{"anchor" => anchor} = params) do
    above = Map.get(params, "above", "true") |> parse_boolean(true)
    below = Map.get(params, "below", "0") |> parse_integer(0)
    _branching_factor = Map.get(params, "branchingFactor", "1") |> parse_integer(1)

    case parse_at_uri(anchor) do
      {:ok, {repo_did, collection, rkey}} ->
        thread_items = build_thread_v2(repo_did, collection, rkey, above, below)

        # Check if there are other replies not included in the response
        has_other_replies = false

        json(conn, %{
          thread: thread_items,
          hasOtherReplies: has_other_replies
        })

      {:error, _} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "InvalidRequest", message: "Invalid AT URI format"})
    end
  end

  def get_post_thread_v2(conn, params) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      error: "InvalidRequest",
      message: "Missing required parameter: anchor. Received params: #{inspect(params)}"
    })
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

  # Build thread v2 as flat array with depth indicators
  defp build_thread_v2(repo_did, collection, rkey, fetch_above, fetch_below) do
    uri = "at://#{repo_did}/#{collection}/#{rkey}"

    case Repositories.get_record(repo_did, collection, rkey) do
      nil ->
        # Anchor post not found
        [%{
          uri: uri,
          depth: 0,
          value: %{
            "$type" => "app.bsky.unspecced.defs#threadItemNotFound"
          }
        }]

      anchor_post ->
        thread_items = []

        # Determine if anchor is the root of the thread (OP)
        is_op = not Map.has_key?(anchor_post.value, "reply")

        # Add parent posts if requested (negative depth)
        thread_items =
          if fetch_above && anchor_post.value["reply"] do
            parent_uri = anchor_post.value["reply"]["parent"]["uri"]
            collect_parents(parent_uri, -1) ++ thread_items
          else
            thread_items
          end

        # Add anchor post at depth 0
        anchor_value = build_thread_item_post(anchor_post, is_op_thread: is_op)
        thread_items = thread_items ++ [%{
          uri: uri,
          depth: 0,
          value: anchor_value
        }]

        # Add replies if requested (positive depth)
        thread_items =
          if fetch_below > 0 do
            replies = collect_replies(repo_did, collection, rkey, 1, fetch_below)
            thread_items ++ replies
          else
            thread_items
          end

        thread_items
    end
  end

  # Collect parent posts (negative depth)
  defp collect_parents(parent_uri, depth) when depth >= -80 do
    case parse_at_uri(parent_uri) do
      {:ok, {repo_did, collection, rkey}} ->
        case Repositories.get_record(repo_did, collection, rkey) do
          nil ->
            [%{
              uri: parent_uri,
              depth: depth,
              value: %{
                "$type" => "app.bsky.unspecced.defs#threadItemNotFound"
              }
            }]

          post ->
            current_item = %{
              uri: parent_uri,
              depth: depth,
              value: build_thread_item_post(post)
            }

            # Recursively get grandparents
            if post.value["reply"] do
              grandparent_uri = post.value["reply"]["parent"]["uri"]
              collect_parents(grandparent_uri, depth - 1) ++ [current_item]
            else
              [current_item]
            end
        end

      {:error, _} ->
        [%{
          uri: parent_uri,
          depth: depth,
          value: %{
            "$type" => "app.bsky.unspecced.defs#threadItemNotFound"
          }
        }]
    end
  end

  defp collect_parents(_, _), do: []

  # Collect reply posts (positive depth)
  defp collect_replies(_repo_did, _collection, _rkey, current_depth, max_depth) when current_depth > max_depth do
    []
  end

  defp collect_replies(repo_did, _collection, rkey, current_depth, max_depth) do
    parent_uri = "at://#{repo_did}/app.bsky.feed.post/#{rkey}"

    # TODO: Implement proper reply lookup with indexing
    # For now, query all posts and filter by reply.parent.uri
    case Repositories.list_records(repo_did, "app.bsky.feed.post", limit: 100) do
      %{records: records} ->
        records
        |> Enum.filter(fn record ->
          reply_parent = get_in(record.value, ["reply", "parent", "uri"])
          reply_parent == parent_uri
        end)
        |> Enum.flat_map(fn reply ->
          reply_uri = "at://#{reply.repository_did}/#{reply.collection}/#{reply.rkey}"

          reply_item = %{
            uri: reply_uri,
            depth: current_depth,
            value: build_thread_item_post(reply)
          }

          # Recursively get nested replies if within depth limit
          nested_replies =
            if current_depth < max_depth do
              collect_replies(repo_did, reply.collection, reply.rkey, current_depth + 1, max_depth)
            else
              []
            end

          [reply_item | nested_replies]
        end)

      _ ->
        []
    end
  end

  # Build thread item post value
  defp build_thread_item_post(record, opts \\ []) do
    author = get_author(record.repository_did)
    uri = "at://#{record.repository_did}/#{record.collection}/#{record.rkey}"
    is_op_thread = Keyword.get(opts, :is_op_thread, false)

    post = %{
      uri: uri,
      cid: record.cid,
      author: author,
      record: record.value,
      bookmarkCount: 0,
      replyCount: 0,
      repostCount: 0,
      likeCount: 0,
      quoteCount: 0,
      indexedAt: DateTime.utc_now() |> DateTime.to_iso8601(),
      viewer: %{
        bookmarked: false,
        threadMuted: false,
        embeddingDisabled: false
      },
      labels: []
    }

    %{
      "$type" => "app.bsky.unspecced.defs#threadItemPost",
      post: post,
      moreParents: false,
      moreReplies: 0,
      opThread: is_op_thread,
      hiddenByThreadgate: false,
      mutedByViewer: false
    }
  end

  # Get author profile
  defp get_author(did) do
    case Accounts.get_account_by_did(did) do
      nil ->
        %{
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

        author_map = %{
          did: account.did,
          handle: account.handle,
          displayName: profile["displayName"],
          avatar: profile["avatar"],
          viewer: %{
            muted: false,
            blockedBy: false
          },
          labels: []
        }

        # Add createdAt if available from account
        author_map =
          if account.inserted_at do
            # Convert NaiveDateTime to DateTime (assume UTC)
            created_at =
              account.inserted_at
              |> DateTime.from_naive!("Etc/UTC")
              |> DateTime.to_iso8601()

            Map.put(author_map, :createdAt, created_at)
          else
            author_map
          end

        # Remove nil values except for viewer and labels
        author_map
        |> Enum.reject(fn
          {:viewer, _} -> false
          {:labels, _} -> false
          {_k, v} -> is_nil(v)
        end)
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

  # Parse boolean with default fallback
  defp parse_boolean("true", _default), do: true
  defp parse_boolean("false", _default), do: false
  defp parse_boolean(value, _default) when is_boolean(value), do: value
  defp parse_boolean(_, default), do: default
end
