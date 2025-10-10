defmodule AetherPDSServer.Repositories do
  @moduledoc """
  The Repositories context.
  Handles all ATProto repository operations.
  """

  import Ecto.Query, warn: false
  alias AetherPDSServer.Repo

  alias AetherPDSServer.Repositories.{
    Repository,
    Commit,
    Record,
    MstBlock,
    Event,
    Blob,
    BlobRef
  }

  # ============================================================================
  # Repository Operations
  # ============================================================================

  @doc """
  Gets a repository by DID.
  """
  def get_repository(did) do
    Repo.get(Repository, did)
  end

  @doc """
  Gets a repository by DID, raises if not found.
  """
  def get_repository!(did) do
    Repo.get!(Repository, did)
  end

  @doc """
  Creates a repository.
  """
  def create_repository(attrs \\ %{}) do
    %Repository{}
    |> Repository.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a repository.
  """
  def update_repository(%Repository{} = repository, attrs) do
    repository
    |> Repository.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a repository and all associated data.
  """
  def delete_repository(%Repository{} = repository) do
    Repo.delete(repository)
  end

  @doc """
  Checks if a repository exists.
  """
  def repository_exists?(did) do
    Repo.exists?(from r in Repository, where: r.did == ^did)
  end

  # ============================================================================
  # Commit Operations
  # ============================================================================

  @doc """
  Gets a commit by repository DID and CID.
  """
  def get_commit(repository_did, cid) do
    Repo.get_by(Commit, repository_did: repository_did, cid: cid)
  end

  @doc """
  Creates a commit.
  """
  def create_commit(attrs \\ %{}) do
    %Commit{}
    |> Commit.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Lists all commits for a repository in chronological order.
  """
  def list_commits(repository_did) do
    Repo.all(
      from c in Commit,
        where: c.repository_did == ^repository_did,
        order_by: [asc: c.inserted_at]
    )
  end

  @doc """
  Gets commits since a specific CID.
  """
  def get_commits_since(repository_did, since_cid) do
    # Get the timestamp of the since_cid
    since_commit = get_commit(repository_did, since_cid)

    if since_commit do
      Repo.all(
        from c in Commit,
          where: c.repository_did == ^repository_did,
          where: c.inserted_at > ^since_commit.inserted_at,
          order_by: [asc: c.inserted_at]
      )
    else
      []
    end
  end

  # ============================================================================
  # Record Operations
  # ============================================================================

  @doc """
  Gets a record by repository DID, collection, and rkey.
  """
  def get_record(repository_did, collection, rkey) do
    Repo.get_by(Record,
      repository_did: repository_did,
      collection: collection,
      rkey: rkey
    )
  end

  @doc """
  Creates a record.
  """
  def create_record(attrs \\ %{}) do
    %Record{}
    |> Record.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a record.
  """
  def update_record(%Record{} = record, attrs) do
    record
    |> Record.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a record.
  """
  def delete_record(%Record{} = record) do
    Repo.delete(record)
  end

  @doc """
  Lists records in a collection.
  """
  def list_records(repository_did, collection, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    cursor = Keyword.get(opts, :cursor)
    reverse = Keyword.get(opts, :reverse, false)

    query =
      from r in Record,
        where: r.repository_did == ^repository_did,
        where: r.collection == ^collection

    query =
      if cursor do
        if reverse do
          from r in query, where: r.rkey < ^cursor
        else
          from r in query, where: r.rkey > ^cursor
        end
      else
        query
      end

    query =
      if reverse do
        from r in query, order_by: [desc: r.rkey], limit: ^limit
      else
        from r in query, order_by: [asc: r.rkey], limit: ^limit
      end

    records = Repo.all(query)

    next_cursor =
      if length(records) == limit do
        List.last(records).rkey
      else
        nil
      end

    %{records: records, cursor: next_cursor}
  end

  @doc """
  Checks if a record exists.
  """
  def record_exists?(repository_did, collection, rkey) do
    Repo.exists?(
      from r in Record,
        where: r.repository_did == ^repository_did,
        where: r.collection == ^collection,
        where: r.rkey == ^rkey
    )
  end

  @doc """
  Lists all collections in a repository.
  """
  def list_collections(repository_did) do
    Repo.all(
      from r in Record,
        where: r.repository_did == ^repository_did,
        distinct: true,
        select: r.collection
    )
  end

  # ============================================================================
  # MST Block Operations
  # ============================================================================

  @doc """
  Gets MST blocks by CIDs.
  """
  def get_mst_blocks(repository_did, cids) when is_list(cids) do
    blocks =
      Repo.all(
        from m in MstBlock,
          where: m.repository_did == ^repository_did,
          where: m.cid in ^cids
      )

    # Return as map of cid => data
    Map.new(blocks, fn block -> {block.cid, block.data} end)
  end

  @doc """
  Creates MST blocks.
  """
  def put_mst_blocks(repository_did, blocks) when is_map(blocks) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    entries =
      Enum.map(blocks, fn {cid, data} ->
        %{
          repository_did: repository_did,
          cid: cid,
          data: data,
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(MstBlock, entries, on_conflict: :nothing)
    :ok
  end

  @doc """
  Gets the MST root CID from the repository HEAD.
  """
  def get_mst_root(repository_did) do
    case get_repository(repository_did) do
      nil -> {:error, :not_found}
      repository -> {:ok, repository.head_cid}
    end
  end

  # ============================================================================
  # Event Operations
  # ============================================================================

  @doc """
  Gets events since a sequence number.
  """
  def get_events_since(seq, limit \\ 100) do
    Repo.all(
      from e in Event,
        where: e.seq > ^seq,
        order_by: [asc: e.seq],
        limit: ^limit
    )
  end

  @doc """
  Gets the current sequence number.
  """
  def get_current_seq do
    result =
      Repo.one(
        from e in Event,
          select: max(e.seq)
      )

    {:ok, result || 0}
  end

  @doc """
  Creates an event.
  """
  def create_event(attrs \\ %{}) do
    %Event{}
    |> Event.changeset(attrs)
    |> Repo.insert()
  end

  # ============================================================================
  # Blob Operations
  # ============================================================================

  @doc """
  Gets a blob by repository DID and CID.
  """
  def get_blob(repository_did, cid) do
    Repo.get_by(Blob, repository_did: repository_did, cid: cid)
  end

  @doc """
  Creates a blob.
  """
  def create_blob(attrs \\ %{}) do
    %Blob{}
    |> Blob.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Deletes a blob.
  """
  def delete_blob(%Blob{} = blob) do
    Repo.delete(blob)
  end

  @doc """
  Deletes a blob with cleanup - removes from MinIO if no longer referenced.
  This should be called when removing blob references to ensure orphaned blobs are cleaned up.
  """
  def cleanup_unreferenced_blob(blob_cid) do
    # Check if blob is still referenced
    if not blob_referenced?(blob_cid) do
      # Find the blob to get its storage_key
      case Repo.get_by(Blob, cid: blob_cid) do
        nil ->
          {:ok, :already_deleted}

        blob ->
          # Delete from MinIO first
          case AetherPDSServer.MinioStorage.delete_blob(blob.storage_key) do
            :ok ->
              # Then delete from database
              case delete_blob(blob) do
                {:ok, _deleted_blob} -> {:ok, :deleted}
                {:error, reason} -> {:error, reason}
              end

            {:error, reason} ->
              # Log error but continue - blob metadata will remain orphaned
              require Logger
              Logger.warning("Failed to delete blob from MinIO: #{inspect(reason)}")
              {:error, :minio_delete_failed}
          end
      end
    else
      {:ok, :still_referenced}
    end
  end

  @doc """
  Lists all blobs for a repository.
  """
  def list_blobs(repository_did) do
    Repo.all(
      from b in Blob,
        where: b.repository_did == ^repository_did
    )
  end

  # ============================================================================
  # Blob Reference Operations
  # ============================================================================

  @doc """
  Creates a blob reference.
  """
  def create_blob_ref(attrs \\ %{}) do
    %BlobRef{}
    |> BlobRef.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Deletes a blob reference.
  """
  def delete_blob_ref(blob_cid, record_uri) do
    Repo.delete_all(
      from br in BlobRef,
        where: br.blob_cid == ^blob_cid,
        where: br.record_uri == ^record_uri
    )
  end

  @doc """
  Gets all records that reference a blob.
  """
  def get_blob_references(blob_cid) do
    Repo.all(
      from br in BlobRef,
        where: br.blob_cid == ^blob_cid,
        select: br.record_uri
    )
  end

  @doc """
  Checks if a blob is referenced by any records.
  """
  def blob_referenced?(blob_cid) do
    Repo.exists?(from br in BlobRef, where: br.blob_cid == ^blob_cid)
  end
end
