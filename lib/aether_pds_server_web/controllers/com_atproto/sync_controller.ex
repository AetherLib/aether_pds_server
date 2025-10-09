# lib/aether_pds_server_web/controllers/sync_controller.ex
defmodule AetherPDSServerWeb.ComATProto.SyncController do
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

      repo ->
        case export_repo_to_car(did, repo) do
          {:ok, car_binary} ->
            conn
            |> put_resp_content_type("application/vnd.ipld.car")
            |> send_resp(200, car_binary)

          {:error, reason} ->
            conn
            |> put_status(:internal_server_error)
            |> json(%{
              error: "ExportFailed",
              message: "Failed to export repository: #{inspect(reason)}"
            })
        end
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

  # ============================================================================
  # CAR Export Helpers
  # ============================================================================

  defp export_repo_to_car(did, repo) do
    alias Aether.ATProto.{CAR, CID}
    alias AetherPDSServer.Repositories

    # 1. Get the latest commit (root of the CAR)
    case CID.parse_cid(repo.head_cid) do
      {:ok, head_cid} ->
        # 2. Get all commits
        commits = Repositories.list_commits(did)

        # 3. Get all records
        records = collect_all_records(did)

        # 4. Get all MST blocks
        mst_blocks = collect_mst_blocks(did)

        # 5. Build CAR blocks
        blocks = []

        # Add commit blocks
        blocks =
          Enum.reduce(commits, blocks, fn commit, acc ->
            with {:ok, commit_cid} <- CID.parse_cid(commit.cid) do
              # Serialize commit data as CBOR
              commit_data = CBOR.encode(commit.data)

              block = %CAR.Block{
                cid: commit_cid,
                data: commit_data
              }

              [block | acc]
            else
              _ -> acc
            end
          end)

        # Add MST blocks
        blocks =
          Enum.reduce(mst_blocks, blocks, fn {cid_str, data}, acc ->
            case CID.parse_cid(cid_str) do
              {:ok, block_cid} ->
                block = %CAR.Block{
                  cid: block_cid,
                  data: data
                }

                [block | acc]

              _ ->
                acc
            end
          end)

        # Add record blocks
        blocks =
          Enum.reduce(records, blocks, fn record, acc ->
            with {:ok, record_cid} <- CID.parse_cid(record.cid) do
              # Serialize record value as CBOR
              record_data = CBOR.encode(record.value)

              block = %CAR.Block{
                cid: record_cid,
                data: record_data
              }

              [block | acc]
            else
              _ -> acc
            end
          end)

        # 6. Create CAR file
        car = %CAR{
          version: 1,
          roots: [head_cid],
          blocks: Enum.reverse(blocks)
        }

        # 7. Encode to binary
        CAR.encode(car)

      {:error, _reason} ->
        {:error, :invalid_head_cid}
    end
  end

  defp collect_all_records(did) do
    # Get all records from all collections
    # Note: This is simplified - in production you'd want pagination
    collections = Repositories.list_collections(did)

    Enum.flat_map(collections, fn collection ->
      result = Repositories.list_records(did, collection, limit: 10000)
      result.records
    end)
  end

  defp collect_mst_blocks(did) do
    # Get all MST blocks for this repository
    # In a real implementation, you'd traverse the MST tree from the root
    # For now, we'll get all blocks stored
    repo = Repositories.get_repository(did)

    if repo && repo.head_cid do
      # Get all commits to find MST root CIDs
      commits = Repositories.list_commits(did)

      mst_cids =
        Enum.flat_map(commits, fn commit ->
          # Extract MST root CID from commit data
          case commit.data do
            %{"data" => mst_cid_str} when is_binary(mst_cid_str) -> [mst_cid_str]
            _ -> []
          end
        end)
        |> Enum.uniq()

      # Fetch all MST blocks
      Repositories.get_mst_blocks(did, mst_cids)
    else
      %{}
    end
  end
end
