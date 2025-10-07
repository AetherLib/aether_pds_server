# lib/aether_pds_server_web/controllers/sync_controller.ex
defmodule AetherPDSServerWeb.SyncController do
  use AetherPDSServerWeb, :controller

  alias AetherPDSServer.Repositories

  @doc """
  GET /xrpc/com.atproto.sync.getRepo

  Export entire repository as CAR file
  """
  def get_repo(conn, %{"did" => did}) do
    case Repositories.get_repository(did) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "RepoNotFound", message: "Repository not found"})

      _repo ->
        # TODO: Generate CAR file export
        conn
        |> put_status(:not_implemented)
        |> json(%{error: "NotImplemented", message: "CAR export not yet implemented"})
    end
  end

  @doc """
  GET /xrpc/com.atproto.sync.getLatestCommit

  Get the latest commit for a repository
  """
  def get_latest_commit(conn, %{"did" => did}) do
    commits = Repositories.list_commits(did)

    case List.last(commits) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "RepoNotFound", message: "Repository not found"})

      commit ->
        response = %{
          cid: commit.cid,
          rev: commit.rev
        }

        json(conn, response)
    end
  end

  @doc """
  GET /xrpc/com.atproto.sync.getRecord

  Get a single record as CAR file
  """
  def get_record(conn, %{"did" => did, "collection" => collection, "rkey" => rkey}) do
    case Repositories.get_record(did, collection, rkey) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "RecordNotFound", message: "Record not found"})

      _record ->
        # TODO: Generate CAR file for record
        conn
        |> put_status(:not_implemented)
        |> json(%{error: "NotImplemented", message: "Record CAR export not yet implemented"})
    end
  end

  @doc """
  GET /xrpc/com.atproto.sync.getBlocks

  Get MST blocks as CAR file
  """
  def get_blocks(conn, %{"did" => did, "cids" => cids}) do
    cid_list = String.split(cids, ",")
    blocks = Repositories.get_mst_blocks(did, cid_list)

    if map_size(blocks) == 0 do
      conn
      |> put_status(:not_found)
      |> json(%{error: "BlocksNotFound", message: "Blocks not found"})
    else
      # TODO: Generate CAR file for blocks
      conn
      |> put_status(:not_implemented)
      |> json(%{error: "NotImplemented", message: "Block CAR export not yet implemented"})
    end
  end

  @doc """
  GET /xrpc/com.atproto.sync.getBlob

  Download a blob
  """
  def get_blob(conn, %{"did" => did, "cid" => cid}) do
    case Repositories.get_blob(did, cid) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "BlobNotFound", message: "Blob not found"})

      blob ->
        conn
        |> put_resp_content_type(blob.mime_type || "application/octet-stream")
        |> send_resp(200, blob.data)
    end
  end

  @doc """
  GET /xrpc/com.atproto.sync.listBlobs

  List all blobs for a repository
  """
  def list_blobs(conn, %{"did" => did} = params) do
    blobs = Repositories.list_blobs(did)
    cids = Enum.map(blobs, & &1.cid)

    limit = params |> Map.get("limit", "500") |> String.to_integer() |> min(1000)

    paginated_cids = Enum.take(cids, limit)
    next_cursor = if length(cids) > limit, do: Enum.at(cids, limit)

    response = %{
      cids: paginated_cids
    }

    response = if next_cursor, do: Map.put(response, :cursor, next_cursor), else: response

    json(conn, response)
  end

  @doc """
  POST /xrpc/com.atproto.sync.notifyOfUpdate (Admin)

  Notify of repository update
  """
  def notify_of_update(conn, _params) do
    # TODO: Implement notification system
    json(conn, %{})
  end

  @doc """
  POST /xrpc/com.atproto.sync.requestCrawl (Admin)

  Request crawling of a repository
  """
  def request_crawl(conn, _params) do
    # TODO: Implement crawl request
    json(conn, %{})
  end
end
