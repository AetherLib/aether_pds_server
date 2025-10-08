# lib/aether_pds_server_web/controllers/bsky/actor_controller.ex
defmodule AetherPDSServerWeb.Bsky.ActorController do
  use AetherPDSServerWeb, :controller

  alias AetherPDSServer.{Accounts, Repositories}

  @doc """
  GET /xrpc/app.bsky.actor.getProfile

  Get detailed profile view of an actor.
  """
  def get_profile(conn, %{"actor" => actor}) do
    # Actor can be a DID or a handle
    account = resolve_actor(actor)

    case account do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "ProfileNotFound", message: "Profile not found"})

      account ->
        # Get the profile record if it exists
        profile = get_profile_record(account.did)

        # Get follower/following counts (stubbed for now)
        {followers_count, follows_count, posts_count} = get_stats(account.did)

        response = %{
          did: account.did,
          handle: account.handle,
          displayName: profile["displayName"],
          description: profile["description"],
          avatar: profile["avatar"],
          banner: profile["banner"],
          followersCount: followers_count,
          followsCount: follows_count,
          postsCount: posts_count,
          indexedAt: DateTime.utc_now() |> DateTime.to_iso8601(),
          # Optional fields
          labels: [],
          viewer: build_viewer_state(conn, account.did)
        }

        # Remove nil values
        response =
          response
          |> Enum.reject(fn {_k, v} -> is_nil(v) end)
          |> Map.new()

        json(conn, response)
    end
  end

  # Resolve actor by DID or handle
  defp resolve_actor(actor) do
    cond do
      String.starts_with?(actor, "did:") ->
        Accounts.get_account_by_did(actor)

      true ->
        Accounts.get_account_by_handle(actor)
    end
  end

  # Get the profile record from the repository
  defp get_profile_record(did) do
    case Repositories.get_record(did, "app.bsky.actor.profile", "self") do
      nil -> %{}
      record -> record.value
    end
  end

  # Get stats for the profile (stubbed - you'll implement these later)
  defp get_stats(did) do
    # TODO: Query actual follow/post counts from database
    followers_count = count_followers(did)
    follows_count = count_follows(did)
    posts_count = count_posts(did)

    {followers_count, follows_count, posts_count}
  end

  defp count_followers(_did) do
    # TODO: Count records in app.bsky.graph.follow where subject = did
    0
  end

  defp count_follows(did) do
    # Count records in app.bsky.graph.follow collection for this user
    case Repositories.list_records(did, "app.bsky.graph.follow", limit: 1000) do
      %{records: records} -> length(records)
      _ -> 0
    end
  end

  defp count_posts(did) do
    # Count records in app.bsky.feed.post collection
    case Repositories.list_records(did, "app.bsky.feed.post", limit: 1000) do
      %{records: records} -> length(records)
      _ -> 0
    end
  end

  # Build viewer state (relationship to current user)
  defp build_viewer_state(conn, profile_did) do
    current_did = conn.assigns[:current_did]

    if current_did && current_did != profile_did do
      # Check if current user follows this profile
      following = check_if_following(current_did, profile_did)
      followed_by = check_if_following(profile_did, current_did)

      %{
        muted: false,
        blockedBy: false,
        following:
          if(following, do: "at://#{current_did}/app.bsky.graph.follow/#{following}", else: nil),
        followedBy:
          if(followed_by,
            do: "at://#{profile_did}/app.bsky.graph.follow/#{followed_by}",
            else: nil
          )
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()
    else
      %{}
    end
  end

  defp check_if_following(follower_did, subject_did) do
    # TODO: Query app.bsky.graph.follow records where subject = subject_did
    # Return rkey if found, nil otherwise
    nil
  end
end
