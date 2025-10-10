defmodule AetherPDSServerWeb.AppBsky.GraphController do
  use AetherPDSServerWeb, :controller

  alias AetherPDSServer.{Accounts, Repositories}

  @doc """
  GET /xrpc/app.bsky.graph.getActorStarterPacks
  """
  def get_actor_starter_packs(conn, _) do
  end

  @doc """
  GET /xrpc/app.bsky.graph.getBlocks

  Get a list of accounts that the current user has blocked.
  Parameters:
  - limit: Number of blocks to return (default: 50, max: 100)
  - cursor: Pagination cursor
  """
  def get_blocks(conn, params) do
    current_did = conn.assigns[:current_did]

    if is_nil(current_did) do
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "AuthRequired", message: "Authentication required"})
    else
      limit = Map.get(params, "limit", "50") |> parse_integer(50) |> min(100)
      cursor = Map.get(params, "cursor")

      # Get block records from the current user
      result =
        Repositories.list_records(current_did, "app.bsky.graph.block",
          limit: limit + 1,
          cursor: cursor
        )

      blocks =
        case result do
          %{records: records} -> records
          _ -> []
        end

      # Paginate
      blocks_to_return = Enum.take(blocks, limit)

      next_cursor =
        if length(blocks) > limit do
          List.last(blocks_to_return).rkey
        else
          nil
        end

      # Build blocked actor views
      blocked_actors =
        blocks_to_return
        |> Enum.map(fn block_record ->
          blocked_did = block_record.value["subject"]
          build_blocked_actor_view(blocked_did, block_record, current_did)
        end)
        |> Enum.reject(&is_nil/1)

      response = %{blocks: blocked_actors}
      response = if next_cursor, do: Map.put(response, :cursor, next_cursor), else: response

      json(conn, response)
    end
  end

  @doc """
  GET /xrpc/app.bsky.graph.getFollowers

  Get a list of accounts that follow the specified actor.
  Parameters:
  - actor: AT Identifier (DID or handle) - required
  - limit: Number of followers to return (default: 50, max: 100)
  - cursor: Pagination cursor
  """
  def get_followers(conn, %{"actor" => actor} = params) do
    current_did = conn.assigns[:current_did]
    limit = Map.get(params, "limit", "50") |> parse_integer(50) |> min(100)
    cursor = Map.get(params, "cursor")

    case resolve_actor(actor) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "ActorNotFound", message: "Actor not found"})

      account ->
        # Find all follow records where subject = this actor's DID
        followers = find_followers(account.did, limit, cursor)

        # Paginate
        followers_to_return = Enum.take(followers, limit)

        next_cursor =
          if length(followers) > limit do
            List.last(followers_to_return).rkey
          else
            nil
          end

        # Build follower views
        follower_views =
          followers_to_return
          |> Enum.map(fn follow_record ->
            follower_did = follow_record.repository_did
            build_follower_view(follower_did, follow_record, current_did)
          end)
          |> Enum.reject(&is_nil/1)

        response = %{
          subject: build_profile_view(account, current_did),
          followers: follower_views
        }

        response = if next_cursor, do: Map.put(response, :cursor, next_cursor), else: response

        json(conn, response)
    end
  end

  def get_followers(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "InvalidRequest", message: "Missing required parameter: actor"})
  end

  @doc """
  GET /xrpc/app.bsky.graph.getFollows

  Get a list of accounts that the specified actor follows.
  Parameters:
  - actor: AT Identifier (DID or handle) - required
  - limit: Number of follows to return (default: 50, max: 100)
  - cursor: Pagination cursor
  """
  def get_follows(conn, %{"actor" => actor} = params) do
    current_did = conn.assigns[:current_did]
    limit = Map.get(params, "limit", "50") |> parse_integer(50) |> min(100)
    cursor = Map.get(params, "cursor")

    case resolve_actor(actor) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "ActorNotFound", message: "Actor not found"})

      account ->
        # Get follow records from this actor
        result =
          Repositories.list_records(account.did, "app.bsky.graph.follow",
            limit: limit + 1,
            cursor: cursor
          )

        follows =
          case result do
            %{records: records} -> records
            _ -> []
          end

        # Paginate
        follows_to_return = Enum.take(follows, limit)

        next_cursor =
          if length(follows) > limit do
            List.last(follows_to_return).rkey
          else
            nil
          end

        # Build follow views
        follow_views =
          follows_to_return
          |> Enum.map(fn follow_record ->
            followed_did = follow_record.value["subject"]
            build_follow_view(followed_did, follow_record, current_did)
          end)
          |> Enum.reject(&is_nil/1)

        response = %{
          subject: build_profile_view(account, current_did),
          follows: follow_views
        }

        response = if next_cursor, do: Map.put(response, :cursor, next_cursor), else: response

        json(conn, response)
    end
  end

  def get_follows(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "InvalidRequest", message: "Missing required parameter: actor"})
  end

  @doc """
  GET /xrpc/app.bsky.graph.getKnownFollowers
  """
  def get_known_followers(conn, _) do
  end

  @doc """
  GET /xrpc/app.bsky.graph.getListBlocks
  """
  def get_list_blocks(conn, _) do
  end

  @doc """
  GET /xrpc/app.bsky.graph.getListMutes
  """
  def get_list_mutes(conn, _) do
  end

  @doc """
  GET /xrpc/app.bsky.graph.getList
  """
  def get_list(conn, _) do
  end

  @doc """
  GET /xrpc/app.bsky.graph.getLists
  """
  def get_lists(conn, _) do
  end

  @doc """
  GET /xrpc/app.bsky.graph.getMutes

  Get a list of accounts that the current user has muted.
  Parameters:
  - limit: Number of mutes to return (default: 50, max: 100)
  - cursor: Pagination cursor
  """
  def get_mutes(conn, params) do
    current_did = conn.assigns[:current_did]

    if is_nil(current_did) do
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "AuthRequired", message: "Authentication required"})
    else
      limit = Map.get(params, "limit", "50") |> parse_integer(50) |> min(100)
      cursor = Map.get(params, "cursor")

      # Get mute records from the current user
      # Note: Mutes are typically stored as app.bsky.graph.mute records
      # but they're not part of the permanent repo - they're temporary preferences
      # For now, we'll check for mute records in the repository
      result =
        Repositories.list_records(current_did, "app.bsky.graph.mute",
          limit: limit + 1,
          cursor: cursor
        )

      mutes =
        case result do
          %{records: records} -> records
          _ -> []
        end

      # Paginate
      mutes_to_return = Enum.take(mutes, limit)

      next_cursor =
        if length(mutes) > limit do
          List.last(mutes_to_return).rkey
        else
          nil
        end

      # Build muted actor views
      muted_actors =
        mutes_to_return
        |> Enum.map(fn mute_record ->
          muted_did = mute_record.value["subject"]
          build_profile_view_basic(muted_did, current_did)
        end)
        |> Enum.reject(&is_nil/1)

      response = %{mutes: muted_actors}
      response = if next_cursor, do: Map.put(response, :cursor, next_cursor), else: response

      json(conn, response)
    end
  end

  @doc """
  GET /xrpc/app.bsky.graph.getRelationships

  Get the relationship state between the current user and other actors.
  Parameters:
  - actor: AT Identifier (DID or handle) - can be provided multiple times
  """
  def get_relationships(conn, params) do
    current_did = conn.assigns[:current_did]

    if is_nil(current_did) do
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "AuthRequired", message: "Authentication required"})
    else
      # Handle both single actor and multiple actors
      actors =
        case Map.get(params, "actor") do
          nil -> []
          actor when is_binary(actor) -> [actor]
          actors when is_list(actors) -> actors
        end

      # Resolve all actors and build relationship views
      relationships =
        actors
        |> Enum.take(30)
        |> Enum.map(fn actor ->
          case resolve_actor(actor) do
            nil -> nil
            account -> build_relationship_view(current_did, account.did)
          end
        end)
        |> Enum.reject(&is_nil/1)

      json(conn, %{relationships: relationships})
    end
  end

  @doc """
  GET /xrpc/app.bsky.graph.getStarterPack
  """
  def get_starter_pack(conn, _) do
  end

  @doc """
  GET /xrpc/app.bsky.graph.getStarterPacks
  """
  def get_starter_packs(conn, _) do
  end

  @doc """
  GET /xrpc/app.bsky.graph.getSuggestedFollowsByActor
  """
  def get_suggested_follows_by_actor(conn, _) do
  end

  @doc """
  POST /xrpc/app.bsky.graph.muteActorList
  """
  def mute_actor_list(conn, _) do
    # TODO: Implement list muting
    conn
    |> put_status(:not_implemented)
    |> json(%{error: "NotImplemented", message: "List muting not yet implemented"})
  end

  @doc """
  POST /xrpc/app.bsky.graph.muteActor

  Mute an actor. Mutes are private and not stored in the repository.
  Parameters:
  - actor: AT Identifier (DID or handle) - required
  """
  def mute_actor(conn, %{"actor" => actor}) do
    current_did = conn.assigns[:current_did]

    if is_nil(current_did) do
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "AuthRequired", message: "Authentication required"})
    else
      case resolve_actor(actor) do
        nil ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "ActorNotFound", message: "Actor not found"})

        account ->
          # Create a mute record
          # Generate a unique rkey for the mute
          rkey = generate_tid()

          mute_value = %{
            "$type" => "app.bsky.graph.mute",
            "subject" => account.did,
            "createdAt" => DateTime.utc_now() |> DateTime.to_iso8601()
          }

          cid = Aether.ATProto.CID.from_map(mute_value)

          case Repositories.create_record(%{
                 repository_did: current_did,
                 collection: "app.bsky.graph.mute",
                 rkey: rkey,
                 cid: cid,
                 value: mute_value
               }) do
            {:ok, _record} ->
              json(conn, %{})

            {:error, reason} ->
              conn
              |> put_status(:bad_request)
              |> json(%{
                error: "InvalidRequest",
                message: "Failed to create mute: #{inspect(reason)}"
              })
          end
      end
    end
  end

  def mute_actor(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "InvalidRequest", message: "Missing required parameter: actor"})
  end

  @doc """
  POST /xrpc/app.bsky.graph.muteThread

  Mute a thread. The thread's root post URI is used to identify the thread.
  Parameters:
  - root: AT URI of the root post - required
  """
  def mute_thread(conn, %{"root" => root_uri}) do
    current_did = conn.assigns[:current_did]

    if is_nil(current_did) do
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "AuthRequired", message: "Authentication required"})
    else
      # Create a thread mute record
      rkey = generate_tid()

      mute_value = %{
        "$type" => "app.bsky.graph.threadMute",
        "root" => root_uri,
        "createdAt" => DateTime.utc_now() |> DateTime.to_iso8601()
      }

      cid = Aether.ATProto.CID.from_map(mute_value)

      case Repositories.create_record(%{
             repository_did: current_did,
             collection: "app.bsky.graph.threadMute",
             rkey: rkey,
             cid: cid,
             value: mute_value
           }) do
        {:ok, _record} ->
          json(conn, %{})

        {:error, reason} ->
          conn
          |> put_status(:bad_request)
          |> json(%{
            error: "InvalidRequest",
            message: "Failed to mute thread: #{inspect(reason)}"
          })
      end
    end
  end

  def mute_thread(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "InvalidRequest", message: "Missing required parameter: root"})
  end

  @doc """
  GET /xrpc/app.bsky.graph.searchStarterPacks
  """
  def search_starter_packs(conn, _) do
  end

  @doc """
  POST /xrpc/app.bsky.graph.unmuteActorList
  """
  def unmute_actor_list(conn, _) do
    # TODO: Implement list unmuting
    conn
    |> put_status(:not_implemented)
    |> json(%{error: "NotImplemented", message: "List unmuting not yet implemented"})
  end

  @doc """
  POST /xrpc/app.bsky.graph.unmuteActor

  Unmute an actor.
  Parameters:
  - actor: AT Identifier (DID or handle) - required
  """
  def unmute_actor(conn, %{"actor" => actor}) do
    current_did = conn.assigns[:current_did]

    if is_nil(current_did) do
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "AuthRequired", message: "Authentication required"})
    else
      case resolve_actor(actor) do
        nil ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "ActorNotFound", message: "Actor not found"})

        account ->
          # Find and delete the mute record
          case find_mute_record(current_did, account.did) do
            nil ->
              # Not muted, return success anyway
              json(conn, %{})

            mute_record ->
              case Repositories.delete_record(mute_record) do
                {:ok, _} ->
                  json(conn, %{})

                {:error, reason} ->
                  conn
                  |> put_status(:bad_request)
                  |> json(%{
                    error: "InvalidRequest",
                    message: "Failed to unmute: #{inspect(reason)}"
                  })
              end
          end
      end
    end
  end

  def unmute_actor(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "InvalidRequest", message: "Missing required parameter: actor"})
  end

  @doc """
  POST /xrpc/app.bsky.graph.unmuteThread

  Unmute a thread.
  Parameters:
  - root: AT URI of the root post - required
  """
  def unmute_thread(conn, %{"root" => root_uri}) do
    current_did = conn.assigns[:current_did]

    if is_nil(current_did) do
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "AuthRequired", message: "Authentication required"})
    else
      # Find and delete the thread mute record
      case find_thread_mute_record(current_did, root_uri) do
        nil ->
          # Not muted, return success anyway
          json(conn, %{})

        mute_record ->
          case Repositories.delete_record(mute_record) do
            {:ok, _} ->
              json(conn, %{})

            {:error, reason} ->
              conn
              |> put_status(:bad_request)
              |> json(%{
                error: "InvalidRequest",
                message: "Failed to unmute thread: #{inspect(reason)}"
              })
          end
      end
    end
  end

  def unmute_thread(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "InvalidRequest", message: "Missing required parameter: root"})
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

  # Find followers for a given DID
  defp find_followers(subject_did, limit, cursor) do
    # Get all accounts and search their follow records
    accounts = Accounts.list_accounts()

    followers =
      accounts
      |> Enum.flat_map(fn account ->
        case Repositories.list_records(account.did, "app.bsky.graph.follow", limit: 1000) do
          %{records: records} ->
            records
            |> Enum.filter(fn record ->
              record.value["subject"] == subject_did
            end)

          _ ->
            []
        end
      end)

    # Apply cursor if present
    followers =
      if cursor do
        Enum.drop_while(followers, fn record -> record.rkey <= cursor end)
      else
        followers
      end

    # Return limit + 1 for pagination
    Enum.take(followers, limit + 1)
  end

  # Build a blocked actor view
  defp build_blocked_actor_view(blocked_did, block_record, current_did) do
    case Accounts.get_account_by_did(blocked_did) do
      nil ->
        nil

      account ->
        profile = get_profile_record(account.did)

        %{
          did: account.did,
          handle: account.handle,
          displayName: profile["displayName"],
          avatar: profile["avatar"],
          viewer: %{
            muted: false,
            blockedBy: false,
            blocking: "at://#{current_did}/app.bsky.graph.block/#{block_record.rkey}"
          },
          labels: []
        }
        |> Enum.reject(fn {k, v} -> k not in [:did, :handle, :viewer, :labels] and is_nil(v) end)
        |> Map.new()
    end
  end

  # Build a follower view
  defp build_follower_view(follower_did, follow_record, current_did) do
    case Accounts.get_account_by_did(follower_did) do
      nil ->
        nil

      account ->
        profile = get_profile_record(account.did)

        %{
          did: account.did,
          handle: account.handle,
          displayName: profile["displayName"],
          avatar: profile["avatar"],
          createdAt:
            Map.get(follow_record.value, "createdAt", format_timestamp(DateTime.utc_now())),
          viewer: build_viewer_state(current_did, account.did),
          labels: []
        }
        |> Enum.reject(fn {k, v} ->
          k not in [:did, :handle, :viewer, :labels, :createdAt] and is_nil(v)
        end)
        |> Map.new()
    end
  end

  # Build a follow view
  defp build_follow_view(followed_did, follow_record, current_did) do
    case Accounts.get_account_by_did(followed_did) do
      nil ->
        nil

      account ->
        profile = get_profile_record(account.did)

        %{
          did: account.did,
          handle: account.handle,
          displayName: profile["displayName"],
          avatar: profile["avatar"],
          createdAt:
            Map.get(follow_record.value, "createdAt", format_timestamp(DateTime.utc_now())),
          viewer: build_viewer_state(current_did, account.did),
          labels: []
        }
        |> Enum.reject(fn {k, v} ->
          k not in [:did, :handle, :viewer, :labels, :createdAt] and is_nil(v)
        end)
        |> Map.new()
    end
  end

  # Build a profile view for an account
  defp build_profile_view(account, current_did) do
    profile = get_profile_record(account.did)

    %{
      did: account.did,
      handle: account.handle,
      displayName: profile["displayName"],
      avatar: profile["avatar"],
      viewer: build_viewer_state(current_did, account.did),
      labels: []
    }
    |> Enum.reject(fn {k, v} -> k not in [:did, :handle, :viewer, :labels] and is_nil(v) end)
    |> Map.new()
  end

  # Build a basic profile view (for mutes list)
  defp build_profile_view_basic(did, current_did) do
    case Accounts.get_account_by_did(did) do
      nil ->
        nil

      account ->
        profile = get_profile_record(account.did)

        %{
          did: account.did,
          handle: account.handle,
          displayName: profile["displayName"],
          avatar: profile["avatar"],
          viewer: build_viewer_state(current_did, account.did),
          labels: []
        }
        |> Enum.reject(fn {k, v} -> k not in [:did, :handle, :viewer, :labels] and is_nil(v) end)
        |> Map.new()
    end
  end

  # Build a relationship view between two actors
  defp build_relationship_view(current_did, target_did) do
    # Check various relationship states
    following_uri = check_if_following(current_did, target_did)
    followed_by_uri = check_if_following(target_did, current_did)
    blocking_uri = check_if_blocking(current_did, target_did)
    blocked_by_uri = check_if_blocking(target_did, current_did)
    muted = check_if_muted(current_did, target_did)

    %{
      "$type" => "app.bsky.graph.defs#relationship",
      did: target_did,
      following: following_uri,
      followedBy: followed_by_uri,
      blocking: blocking_uri,
      blockedBy: blocked_by_uri,
      muted: muted
    }
    |> Enum.reject(fn {k, v} -> k not in [:"$type", :did, :muted] and is_nil(v) end)
    |> Map.new()
  end

  # Build viewer state for a profile
  defp build_viewer_state(nil, _profile_did) do
    %{
      muted: false,
      blockedBy: false
    }
  end

  defp build_viewer_state(current_did, profile_did) when current_did == profile_did do
    %{
      muted: false,
      blockedBy: false
    }
  end

  defp build_viewer_state(current_did, profile_did) do
    # Check if current user follows this profile
    following_uri = check_if_following(current_did, profile_did)
    followed_by_uri = check_if_following(profile_did, current_did)
    blocking_uri = check_if_blocking(current_did, profile_did)
    blocked_by_uri = check_if_blocking(profile_did, current_did)
    muted = check_if_muted(current_did, profile_did)

    viewer = %{
      muted: muted,
      blockedBy: blocked_by_uri != nil
    }

    viewer = if following_uri, do: Map.put(viewer, :following, following_uri), else: viewer
    viewer = if followed_by_uri, do: Map.put(viewer, :followedBy, followed_by_uri), else: viewer
    viewer = if blocking_uri, do: Map.put(viewer, :blocking, blocking_uri), else: viewer

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

  # Check if blocker_did blocks subject_did, return block record URI if found
  defp check_if_blocking(blocker_did, subject_did) do
    case Repositories.list_records(blocker_did, "app.bsky.graph.block", limit: 1000) do
      %{records: records} ->
        records
        |> Enum.find(fn record ->
          record.value["subject"] == subject_did
        end)
        |> case do
          nil -> nil
          record -> "at://#{record.repository_did}/app.bsky.graph.block/#{record.rkey}"
        end

      _ ->
        nil
    end
  end

  # Check if muter_did mutes subject_did
  defp check_if_muted(muter_did, subject_did) do
    case find_mute_record(muter_did, subject_did) do
      nil -> false
      _ -> true
    end
  end

  # Find mute record
  defp find_mute_record(muter_did, subject_did) do
    case Repositories.list_records(muter_did, "app.bsky.graph.mute", limit: 1000) do
      %{records: records} ->
        Enum.find(records, fn record ->
          record.value["subject"] == subject_did
        end)

      _ ->
        nil
    end
  end

  # Find thread mute record
  defp find_thread_mute_record(muter_did, root_uri) do
    case Repositories.list_records(muter_did, "app.bsky.graph.threadMute", limit: 1000) do
      %{records: records} ->
        Enum.find(records, fn record ->
          record.value["root"] == root_uri
        end)

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

  # Format timestamp to ISO8601 with milliseconds
  defp format_timestamp(datetime) do
    datetime
    |> DateTime.truncate(:millisecond)
    |> DateTime.to_iso8601()
  end

  # Generate TID (Timestamp Identifier) for rkey
  defp generate_tid do
    # Simple TID generation using microsecond timestamp
    now = DateTime.utc_now()
    timestamp_us = DateTime.to_unix(now, :microsecond)
    Base.encode32(<<timestamp_us::64>>, padding: false, case: :lower)
  end
end
