defmodule AetherPDSServer.Federation do
  @moduledoc """
  Handles cross-server communication and federation for AT Protocol.

  This module provides functions to:
  - Discover remote PDS servers from handles or DIDs
  - Fetch records from remote PDS servers
  - Verify commits and records from remote servers
  - Cache service endpoints for performance

  ## Examples

      # Discover remote PDS
      iex> Federation.discover_pds("alice.bsky.social")
      {:ok, "https://morel.us-east.host.bsky.network"}

      # Fetch remote record
      iex> Federation.fetch_remote_record("did:plc:abc123", "app.bsky.feed.post", "abc123")
      {:ok, %{"text" => "Hello from remote server!"}}
  """

  require Logger

  alias AetherPDSServer.DIDResolver

  @doc """
  Discovers the PDS endpoint for a handle or DID.

  Returns the PDS endpoint URL where the user's data is hosted.

  ## Examples

      iex> discover_pds("alice.bsky.social")
      {:ok, "https://pds.example.com"}

      iex> discover_pds("did:plc:abc123")
      {:ok, "https://pds.example.com"}
  """
  def discover_pds("did:" <> _ = did) do
    Logger.debug("Discovering PDS for DID: #{did}")

    with {:ok, did_doc} <- DIDResolver.resolve_did(did),
         {:ok, pds_endpoint} <- DIDResolver.get_pds_endpoint(did_doc) do
      Logger.info("Discovered PDS for #{did}: #{pds_endpoint}")
      {:ok, pds_endpoint}
    else
      {:error, reason} = error ->
        Logger.error("Failed to discover PDS for #{did}: #{inspect(reason)}")
        error
    end
  end

  def discover_pds(handle) when is_binary(handle) do
    Logger.debug("Discovering PDS for handle: #{handle}")

    with {:ok, did} <- DIDResolver.resolve_handle(handle),
         {:ok, pds_endpoint} <- discover_pds(did) do
      Logger.info("Discovered PDS for #{handle}: #{pds_endpoint}")
      {:ok, pds_endpoint}
    else
      {:error, reason} = error ->
        Logger.error("Failed to discover PDS for #{handle}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Fetches a record from a remote PDS server.

  ## Parameters
  - did: The DID of the repository
  - collection: The collection namespace (e.g., "app.bsky.feed.post")
  - rkey: The record key

  ## Examples

      iex> fetch_remote_record("did:plc:abc123", "app.bsky.feed.post", "abc123")
      {:ok, %{"uri" => "at://...", "value" => %{"text" => "Hello!"}}}
  """
  def fetch_remote_record(did, collection, rkey) do
    Logger.debug("Fetching remote record: #{did}/#{collection}/#{rkey}")

    with {:ok, pds_endpoint} <- discover_pds(did),
         {:ok, record} <- fetch_record_from_pds(pds_endpoint, did, collection, rkey) do
      Logger.info("Fetched remote record: #{did}/#{collection}/#{rkey}")
      {:ok, record}
    else
      {:error, reason} = error ->
        Logger.error(
          "Failed to fetch remote record #{did}/#{collection}/#{rkey}: #{inspect(reason)}"
        )

        error
    end
  end

  @doc """
  Fetches multiple records from a remote PDS server.

  ## Parameters
  - did: The DID of the repository
  - collection: The collection namespace
  - opts: Optional parameters
    - :limit - Maximum number of records to fetch (default: 50)
    - :cursor - Pagination cursor

  ## Examples

      iex> fetch_remote_records("did:plc:abc123", "app.bsky.feed.post", limit: 10)
      {:ok, %{"records" => [...], "cursor" => "..."}}
  """
  def fetch_remote_records(did, collection, opts \\ []) do
    Logger.debug("Fetching remote records: #{did}/#{collection}")

    with {:ok, pds_endpoint} <- discover_pds(did),
         {:ok, records} <- list_records_from_pds(pds_endpoint, did, collection, opts) do
      Logger.info(
        "Fetched #{length(Map.get(records, "records", []))} records from #{did}/#{collection}"
      )

      {:ok, records}
    else
      {:error, reason} = error ->
        Logger.error("Failed to fetch remote records #{did}/#{collection}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Verifies a remote repository's integrity by checking commits.

  This would verify:
  - Commit signatures
  - MST roots
  - CID chains

  Note: This is a placeholder for full implementation.
  """
  def verify_remote_repository(did) do
    Logger.debug("Verifying remote repository: #{did}")

    with {:ok, pds_endpoint} <- discover_pds(did),
         {:ok, _repo_data} <- describe_repo_from_pds(pds_endpoint, did) do
      # TODO: Implement full verification
      Logger.info("Repository #{did} verified (basic check)")
      {:ok, :verified}
    else
      {:error, reason} = error ->
        Logger.error("Failed to verify repository #{did}: #{inspect(reason)}")
        error
    end
  end

  # Private functions

  defp fetch_record_from_pds(pds_endpoint, did, collection, rkey) do
    url = "#{pds_endpoint}/xrpc/com.atproto.repo.getRecord"

    params = %{
      repo: did,
      collection: collection,
      rkey: rkey
    }

    make_xrpc_request(url, params)
  end

  defp list_records_from_pds(pds_endpoint, did, collection, opts) do
    url = "#{pds_endpoint}/xrpc/com.atproto.repo.listRecords"

    params =
      %{
        repo: did,
        collection: collection
      }
      |> maybe_put(:limit, Keyword.get(opts, :limit))
      |> maybe_put(:cursor, Keyword.get(opts, :cursor))

    make_xrpc_request(url, params)
  end

  defp describe_repo_from_pds(pds_endpoint, did) do
    url = "#{pds_endpoint}/xrpc/com.atproto.repo.describeRepo"
    params = %{repo: did}

    make_xrpc_request(url, params)
  end

  defp make_xrpc_request(url, params) do
    base_opts = Application.get_env(:aether_pds_server, :req_options, [])

    case Req.get(url, [params: params] ++ base_opts) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        case Jason.decode(body) do
          {:ok, decoded} -> {:ok, decoded}
          {:error, _} -> {:error, :invalid_json}
        end

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status}} ->
        Logger.warning("XRPC request failed with status #{status}: #{url}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.error("XRPC request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
