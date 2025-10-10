defmodule AetherPDSServerWeb.AppBsky.NotificationController do
  use AetherPDSServerWeb, :controller

  alias AetherPDSServer.{Accounts, Repositories}

  @doc """
  GET /xrpc/app.bsky.notification.getUnreadCount

  Get the count of unread notifications for the current user.
  Parameters:
  - seenAt: ISO8601 timestamp - only count notifications after this time (optional)
  - priority: Whether to only count priority notifications (optional)
  """
  def get_unread_count(conn, params) do
    current_did = conn.assigns[:current_did]

    if is_nil(current_did) do
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "AuthRequired", message: "Authentication required"})
    else
      seen_at = Map.get(params, "seenAt")
      priority = Map.get(params, "priority", "false") |> parse_boolean(false)

      # Get the user's last seen timestamp from preferences if not provided
      seen_at =
        seen_at || get_last_seen_timestamp(current_did) || "1970-01-01T00:00:00.000Z"

      # Generate notifications and count unread
      notifications = generate_notifications(current_did)

      unread_count =
        notifications
        |> filter_by_seen_at(seen_at)
        |> filter_by_priority(priority)
        |> length()

      json(conn, %{count: unread_count})
    end
  end

  @doc """
  GET /xrpc/app.bsky.notification.listNotifications

  List notifications for the current user.
  Parameters:
  - limit: Number of notifications to return (default: 50, max: 100)
  - cursor: Pagination cursor
  - seenAt: ISO8601 timestamp - filter notifications after this time (optional)
  - priority: Whether to only show priority notifications (optional)
  """
  def list_notifications(conn, params) do
    current_did = conn.assigns[:current_did]

    if is_nil(current_did) do
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "AuthRequired", message: "Authentication required"})
    else
      limit = Map.get(params, "limit", "50") |> parse_integer(50) |> min(100)
      cursor = Map.get(params, "cursor")
      seen_at = Map.get(params, "seenAt")
      priority = Map.get(params, "priority", "false") |> parse_boolean(false)

      # Generate notifications
      notifications = generate_notifications(current_did)

      # Apply filters
      filtered_notifications =
        notifications
        |> filter_by_priority(priority)
        |> apply_cursor(cursor)

      # Paginate
      notifications_to_return = Enum.take(filtered_notifications, limit)

      next_cursor =
        if length(filtered_notifications) > limit do
          last_notif = List.last(notifications_to_return)
          last_notif.indexedAt
        else
          nil
        end

      # Get the user's last seen timestamp
      last_seen = seen_at || get_last_seen_timestamp(current_did)

      response = %{
        notifications: notifications_to_return,
        seenAt: last_seen
      }

      response = if next_cursor, do: Map.put(response, :cursor, next_cursor), else: response

      json(conn, response)
    end
  end

  @doc """
  POST /xrpc/app.bsky.notification.putPreferences

  Update notification preferences (not yet implemented).
  """
  def put_preferences(conn, _params) do
    conn
    |> put_status(:not_implemented)
    |> json(%{error: "NotImplemented", message: "Notification preferences not yet implemented"})
  end

  @doc """
  POST /xrpc/app.bsky.notification.registerPush

  Register a device for push notifications (not yet implemented).
  """
  def register_push(conn, _params) do
    conn
    |> put_status(:not_implemented)
    |> json(%{error: "NotImplemented", message: "Push notifications not yet implemented"})
  end

  @doc """
  POST /xrpc/app.bsky.notification.updateSeen

  Update the last seen timestamp for notifications.
  Parameters:
  - seenAt: ISO8601 timestamp - the time at which notifications were last seen (required)
  """
  def update_seen(conn, %{"seenAt" => seen_at}) do
    current_did = conn.assigns[:current_did]

    if is_nil(current_did) do
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "AuthRequired", message: "Authentication required"})
    else
      # Validate the timestamp
      case DateTime.from_iso8601(seen_at) do
        {:ok, _dt, _} ->
          # Store the seen_at timestamp in user preferences
          case update_last_seen_timestamp(current_did, seen_at) do
            {:ok, _} ->
              json(conn, %{})

            {:error, reason} ->
              conn
              |> put_status(:bad_request)
              |> json(%{
                error: "InvalidRequest",
                message: "Failed to update seen timestamp: #{inspect(reason)}"
              })
          end

        _ ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "InvalidRequest", message: "Invalid seenAt timestamp format"})
      end
    end
  end

  def update_seen(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "InvalidRequest", message: "Missing required parameter: seenAt"})
  end

  # --------------
  # Helper Functions
  # --------------

  # Generate notifications for the current user
  defp generate_notifications(user_did) do
    # Get all accounts to check for interactions
    accounts = Accounts.list_accounts()

    notifications =
      accounts
      |> Enum.flat_map(fn account ->
        generate_notifications_from_account(user_did, account.did)
      end)
      |> Enum.sort_by(fn notif -> notif.indexedAt end, :desc)

    notifications
  end

  # Generate notifications from a specific account's interactions
  defp generate_notifications_from_account(user_did, actor_did) do
    notifications = []

    # 1. Check for follows
    notifications = notifications ++ check_follow_notifications(user_did, actor_did)

    # 2. Check for likes on user's posts
    notifications = notifications ++ check_like_notifications(user_did, actor_did)

    # 3. Check for reposts of user's posts
    notifications = notifications ++ check_repost_notifications(user_did, actor_did)

    # 4. Check for replies to user's posts
    notifications = notifications ++ check_reply_notifications(user_did, actor_did)

    # 5. Check for mentions in posts
    notifications = notifications ++ check_mention_notifications(user_did, actor_did)

    # 6. Check for quote posts
    notifications = notifications ++ check_quote_notifications(user_did, actor_did)

    notifications
  end

  # Check for follow notifications
  defp check_follow_notifications(user_did, actor_did) do
    # Don't notify about self-follows
    if actor_did == user_did do
      []
    else
      case Repositories.list_records(actor_did, "app.bsky.graph.follow", limit: 1000) do
        %{records: records} ->
          records
          |> Enum.filter(fn record ->
            record.value["subject"] == user_did
          end)
          |> Enum.map(fn record ->
            build_follow_notification(actor_did, record)
          end)

        _ ->
          []
      end
    end
  end

  # Check for like notifications
  defp check_like_notifications(user_did, actor_did) do
    # Don't notify about self-likes
    if actor_did == user_did do
      []
    else
      # Get all likes from this actor
      case Repositories.list_records(actor_did, "app.bsky.feed.like", limit: 1000) do
        %{records: like_records} ->
          like_records
          |> Enum.filter(fn like ->
            # Check if the like is for one of the user's posts
            subject_uri = get_in(like.value, ["subject", "uri"])
            is_user_post?(subject_uri, user_did)
          end)
          |> Enum.map(fn like ->
            build_like_notification(actor_did, like)
          end)

        _ ->
          []
      end
    end
  end

  # Check for repost notifications
  defp check_repost_notifications(user_did, actor_did) do
    # Don't notify about self-reposts
    if actor_did == user_did do
      []
    else
      case Repositories.list_records(actor_did, "app.bsky.feed.repost", limit: 1000) do
        %{records: repost_records} ->
          repost_records
          |> Enum.filter(fn repost ->
            subject_uri = get_in(repost.value, ["subject", "uri"])
            is_user_post?(subject_uri, user_did)
          end)
          |> Enum.map(fn repost ->
            build_repost_notification(actor_did, repost)
          end)

        _ ->
          []
      end
    end
  end

  # Check for reply notifications
  defp check_reply_notifications(user_did, actor_did) do
    # Don't notify about self-replies (but allow them as they might be threads)
    case Repositories.list_records(actor_did, "app.bsky.feed.post", limit: 1000) do
      %{records: post_records} ->
        post_records
        |> Enum.filter(fn post ->
          # Check if this is a reply to the user's post
          parent_uri = get_in(post.value, ["reply", "parent", "uri"])
          parent_uri && is_user_post?(parent_uri, user_did) && actor_did != user_did
        end)
        |> Enum.map(fn post ->
          build_reply_notification(actor_did, post)
        end)

      _ ->
        []
    end
  end

  # Check for mention notifications
  defp check_mention_notifications(user_did, actor_did) do
    # Get the user's handle
    case Accounts.get_account_by_did(user_did) do
      nil ->
        []

      user_account ->
        user_handle = user_account.handle

        case Repositories.list_records(actor_did, "app.bsky.feed.post", limit: 1000) do
          %{records: post_records} ->
            post_records
            |> Enum.filter(fn post ->
              # Check if post contains mentions of this user
              has_mention?(post.value, user_handle, user_did)
            end)
            |> Enum.map(fn post ->
              build_mention_notification(actor_did, post)
            end)

          _ ->
            []
        end
    end
  end

  # Check for quote post notifications
  defp check_quote_notifications(user_did, actor_did) do
    # Don't notify about self-quotes
    if actor_did == user_did do
      []
    else
      case Repositories.list_records(actor_did, "app.bsky.feed.post", limit: 1000) do
        %{records: post_records} ->
          post_records
          |> Enum.filter(fn post ->
            # Check if this post quotes one of the user's posts
            embed_uri = get_in(post.value, ["embed", "record", "uri"])
            embed_uri && is_user_post?(embed_uri, user_did)
          end)
          |> Enum.map(fn post ->
            build_quote_notification(actor_did, post)
          end)

        _ ->
          []
      end
    end
  end

  # Check if a URI belongs to a user's post
  defp is_user_post?(uri, user_did) when is_binary(uri) do
    String.starts_with?(uri, "at://#{user_did}/")
  end

  defp is_user_post?(_, _), do: false

  # Check if a post has a mention of the user
  defp has_mention?(post_value, user_handle, user_did) do
    facets = Map.get(post_value, "facets", [])

    Enum.any?(facets, fn facet ->
      features = Map.get(facet, "features", [])

      Enum.any?(features, fn feature ->
        case feature["$type"] do
          "app.bsky.richtext.facet#mention" ->
            feature["did"] == user_did

          _ ->
            false
        end
      end)
    end) ||
      # Fallback: check if handle appears in text (simple mention detection)
      String.contains?(Map.get(post_value, "text", ""), "@#{user_handle}")
  end

  # Build notification objects
  defp build_follow_notification(actor_did, follow_record) do
    %{
      uri: "at://#{follow_record.repository_did}/#{follow_record.collection}/#{follow_record.rkey}",
      cid: follow_record.cid,
      author: build_actor_profile(actor_did),
      reason: "follow",
      reasonSubject: nil,
      isRead: false,
      indexedAt:
        Map.get(follow_record.value, "createdAt", format_timestamp(DateTime.utc_now())),
      labels: []
    }
    |> remove_nil_values()
  end

  defp build_like_notification(actor_did, like_record) do
    subject_uri = get_in(like_record.value, ["subject", "uri"])

    %{
      uri: "at://#{like_record.repository_did}/#{like_record.collection}/#{like_record.rkey}",
      cid: like_record.cid,
      author: build_actor_profile(actor_did),
      reason: "like",
      reasonSubject: subject_uri,
      record: like_record.value,
      isRead: false,
      indexedAt:
        Map.get(like_record.value, "createdAt", format_timestamp(DateTime.utc_now())),
      labels: []
    }
    |> remove_nil_values()
  end

  defp build_repost_notification(actor_did, repost_record) do
    subject_uri = get_in(repost_record.value, ["subject", "uri"])

    %{
      uri: "at://#{repost_record.repository_did}/#{repost_record.collection}/#{repost_record.rkey}",
      cid: repost_record.cid,
      author: build_actor_profile(actor_did),
      reason: "repost",
      reasonSubject: subject_uri,
      record: repost_record.value,
      isRead: false,
      indexedAt:
        Map.get(repost_record.value, "createdAt", format_timestamp(DateTime.utc_now())),
      labels: []
    }
    |> remove_nil_values()
  end

  defp build_reply_notification(actor_did, post_record) do
    parent_uri = get_in(post_record.value, ["reply", "parent", "uri"])

    %{
      uri: "at://#{post_record.repository_did}/#{post_record.collection}/#{post_record.rkey}",
      cid: post_record.cid,
      author: build_actor_profile(actor_did),
      reason: "reply",
      reasonSubject: parent_uri,
      record: post_record.value,
      isRead: false,
      indexedAt:
        Map.get(post_record.value, "createdAt", format_timestamp(DateTime.utc_now())),
      labels: []
    }
    |> remove_nil_values()
  end

  defp build_mention_notification(actor_did, post_record) do
    %{
      uri: "at://#{post_record.repository_did}/#{post_record.collection}/#{post_record.rkey}",
      cid: post_record.cid,
      author: build_actor_profile(actor_did),
      reason: "mention",
      reasonSubject: nil,
      record: post_record.value,
      isRead: false,
      indexedAt:
        Map.get(post_record.value, "createdAt", format_timestamp(DateTime.utc_now())),
      labels: []
    }
    |> remove_nil_values()
  end

  defp build_quote_notification(actor_did, post_record) do
    subject_uri = get_in(post_record.value, ["embed", "record", "uri"])

    %{
      uri: "at://#{post_record.repository_did}/#{post_record.collection}/#{post_record.rkey}",
      cid: post_record.cid,
      author: build_actor_profile(actor_did),
      reason: "quote",
      reasonSubject: subject_uri,
      record: post_record.value,
      isRead: false,
      indexedAt:
        Map.get(post_record.value, "createdAt", format_timestamp(DateTime.utc_now())),
      labels: []
    }
    |> remove_nil_values()
  end

  # Build actor profile for notifications
  defp build_actor_profile(did) do
    case Accounts.get_account_by_did(did) do
      nil ->
        %{
          did: did,
          handle: "unknown.handle",
          displayName: nil,
          avatar: nil,
          labels: []
        }

      account ->
        profile = get_profile_record(account.did)

        %{
          did: account.did,
          handle: account.handle,
          displayName: profile["displayName"],
          avatar: profile["avatar"],
          labels: []
        }
        |> remove_nil_values()
    end
  end

  # Get profile record
  defp get_profile_record(did) do
    case Repositories.get_record(did, "app.bsky.actor.profile", "self") do
      nil -> %{}
      record -> record.value
    end
  end

  # Filter notifications by seen_at timestamp
  defp filter_by_seen_at(notifications, seen_at) do
    case DateTime.from_iso8601(seen_at) do
      {:ok, seen_dt, _} ->
        Enum.filter(notifications, fn notif ->
          case DateTime.from_iso8601(notif.indexedAt) do
            {:ok, notif_dt, _} -> DateTime.compare(notif_dt, seen_dt) == :gt
            _ -> false
          end
        end)

      _ ->
        notifications
    end
  end

  # Filter notifications by priority (for now, all notifications are normal priority)
  defp filter_by_priority(notifications, _priority) do
    # TODO: Implement priority filtering when we have priority logic
    notifications
  end

  # Apply cursor to notifications
  defp apply_cursor(notifications, nil), do: notifications

  defp apply_cursor(notifications, cursor) do
    case DateTime.from_iso8601(cursor) do
      {:ok, cursor_dt, _} ->
        Enum.drop_while(notifications, fn notif ->
          case DateTime.from_iso8601(notif.indexedAt) do
            {:ok, notif_dt, _} -> DateTime.compare(notif_dt, cursor_dt) != :lt
            _ -> false
          end
        end)

      _ ->
        notifications
    end
  end

  # Get last seen timestamp from user preferences
  defp get_last_seen_timestamp(did) do
    case Repositories.get_record(did, "app.bsky.notification.lastSeen", "self") do
      nil -> nil
      record -> record.value["seenAt"]
    end
  end

  # Update last seen timestamp in user preferences
  defp update_last_seen_timestamp(did, seen_at) do
    value = %{
      "$type" => "app.bsky.notification.lastSeen",
      "seenAt" => seen_at
    }

    cid = Aether.ATProto.CID.from_map(value)

    case Repositories.get_record(did, "app.bsky.notification.lastSeen", "self") do
      nil ->
        Repositories.create_record(%{
          repository_did: did,
          collection: "app.bsky.notification.lastSeen",
          rkey: "self",
          cid: cid,
          value: value
        })

      record ->
        Repositories.update_record(record, %{cid: cid, value: value})
    end
  end

  # Remove nil values from maps
  defp remove_nil_values(map) do
    map
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
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

  # Format timestamp to ISO8601 with milliseconds
  defp format_timestamp(datetime) do
    datetime
    |> DateTime.truncate(:millisecond)
    |> DateTime.to_iso8601()
  end
end
