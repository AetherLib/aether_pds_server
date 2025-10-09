# lib/aether_pds_server_web/controllers/bsky/actor_controller.ex
defmodule AetherPDSServerWeb.AppBsky.ActorController do
  use AetherPDSServerWeb, :controller

  alias AetherPDSServer.{Accounts, Repositories}

  @doc """
  GET /xrpc/app.bsky.actor.getPreferences

  Get private preferences attached to the current account.
  """
  def get_preferences(conn, _params) do
    current_did = conn.assigns[:current_did]

    # Get preferences record if it exists
    preferences = get_preferences_record(current_did)

    json(conn, %{preferences: preferences})
  end

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

  @doc """
  GET /xrpc/app.bsky.actor.getProfiles

  Get detailed profile views of multiple actors.
  """
  def get_profiles(conn, %{"actors" => actors}) when is_list(actors) do
    # Resolve all actors and build their profiles
    profiles =
      actors
      |> Enum.map(fn actor ->
        case resolve_actor(actor) do
          nil ->
            nil

          account ->
            profile = get_profile_record(account.did)
            {followers_count, follows_count, posts_count} = get_stats(account.did)

            %{
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
              labels: [],
              viewer: build_viewer_state(conn, account.did)
            }
            |> Enum.reject(fn {_k, v} -> is_nil(v) end)
            |> Map.new()
        end
      end)
      |> Enum.reject(&is_nil/1)

    json(conn, %{profiles: profiles})
  end

  # Handle single actor (when Phoenix doesn't parse as list)
  def get_profiles(conn, %{"actors" => actor}) when is_binary(actor) do
    get_profiles(conn, %{"actors" => [actor]})
  end

  # Handle missing actors parameter
  def get_profiles(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "InvalidRequest", message: "Missing required parameter: actors"})
  end

  @doc """
  GET /xrpc/app.bsky.actor.getSuggestions

  Get a list of suggested actors. Returns empty array for now.
  """
  def get_suggestions(conn, params) do
    limit = Map.get(params, "limit", "50") |> String.to_integer()
    cursor = Map.get(params, "cursor")

    # TODO: Implement actual suggestion algorithm
    # For now, return empty suggestions
    json(conn, %{
      cursor: cursor,
      actors: []
    })
  end

  @doc """
  POST /xrpc/app.bsky.actor.putPreferences

  Set the private preferences attached to the account.
  """
  def put_preferences(conn, %{"preferences" => preferences}) do
    current_did = conn.assigns[:current_did]

    # Store preferences as a record in the repository
    case put_preferences_record(current_did, preferences) do
      {:ok, _} ->
        json(conn, %{})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          error: "InvalidRequest",
          message: "Failed to save preferences: #{inspect(reason)}"
        })
    end
  end

  @doc """
  GET /xrpc/app.bsky.actor.searchActorsTypeahead

  Find actors matching search criteria, optimized for typeahead autocomplete.
  """
  def search_actors_typeahead(conn, params) do
    query = Map.get(params, "q", "")
    limit = Map.get(params, "limit", "10") |> parse_integer(10)

    actors =
      if String.length(query) > 0 do
        search_actors_by_query(query, limit)
      else
        []
      end

    json(conn, %{actors: actors})
  end

  @doc """
  GET /xrpc/app.bsky.actor.searchActors

  Find actors matching search criteria.
  """
  def search_actors(conn, params) do
    query = Map.get(params, "q", "")
    limit = Map.get(params, "limit", "25") |> parse_integer(25)
    cursor = Map.get(params, "cursor")

    {actors, next_cursor} =
      if String.length(query) > 0 do
        search_actors_with_cursor(query, limit, cursor)
      else
        {[], nil}
      end

    response = %{actors: actors}
    response = if next_cursor, do: Map.put(response, :cursor, next_cursor), else: response

    json(conn, response)
  end

  # --------------
  # Helpers
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
    # Query app.bsky.graph.follow records where subject = subject_did
    case Repositories.list_records(follower_did, "app.bsky.graph.follow", limit: 1000) do
      %{records: records} ->
        records
        |> Enum.find(fn record ->
          record.value["subject"] == subject_did
        end)
        |> case do
          nil -> nil
          record -> record.rkey
        end

      _ ->
        nil
    end
  end

  # Get preferences from the actor's repository
  defp get_preferences_record(did) do
    case Repositories.get_record(did, "app.bsky.actor.preferences", "self") do
      nil -> []
      record -> record.value["preferences"] || []
    end
  end

  # Store preferences in the actor's repository
  defp put_preferences_record(did, preferences) do
    alias Aether.ATProto.CID

    value = %{"preferences" => preferences}
    cid = CID.from_map(value)

    case Repositories.get_record(did, "app.bsky.actor.preferences", "self") do
      nil ->
        Repositories.create_record(%{
          repository_did: did,
          collection: "app.bsky.actor.preferences",
          rkey: "self",
          cid: cid,
          value: value
        })

      record ->
        Repositories.update_record(record, %{cid: cid, value: value})
    end
  end

  # Search for actors by handle or DID
  defp search_actors_by_query(query, limit) do
    query_lower = String.downcase(query)

    Accounts.list_accounts()
    |> Enum.filter(fn account ->
      String.contains?(String.downcase(account.handle), query_lower) ||
        String.contains?(String.downcase(account.did), query_lower)
    end)
    |> Enum.take(limit)
    |> Enum.map(&build_actor_view/1)
  end

  # Search actors with cursor support
  defp search_actors_with_cursor(query, limit, cursor) do
    query_lower = String.downcase(query)

    actors =
      Accounts.list_accounts()
      |> Enum.filter(fn account ->
        String.contains?(String.downcase(account.handle), query_lower) ||
          String.contains?(String.downcase(account.did), query_lower)
      end)

    # Apply cursor filtering if present
    actors =
      if cursor do
        Enum.drop_while(actors, fn account -> account.handle <= cursor end)
      else
        actors
      end

    # Take limit + 1 to check if there are more results
    paginated = Enum.take(actors, limit + 1)
    actors_to_return = Enum.take(paginated, limit)

    next_cursor =
      if length(paginated) > limit do
        List.last(actors_to_return).handle
      else
        nil
      end

    {Enum.map(actors_to_return, &build_actor_view/1), next_cursor}
  end

  # Build a simple actor view (for search results)
  defp build_actor_view(account) do
    profile = get_profile_record(account.did)

    %{
      did: account.did,
      handle: account.handle,
      displayName: profile["displayName"],
      avatar: profile["avatar"],
      description: profile["description"],
      indexedAt: DateTime.utc_now() |> DateTime.to_iso8601()
    }
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

  defp parse_integer(value, default) when is_integer(value), do: value
  defp parse_integer(_, default), do: default
end
