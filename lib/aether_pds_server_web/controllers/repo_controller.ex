defmodule AetherPDSServerWeb.RepoController do
  @moduledoc """
  XRPC Controller for ATProto Repository Operations
  """
  use AetherPDSServerWeb, :controller

  alias AetherPDSServer.Repositories
  alias AetherPDSServer.Repositories.{Repository, Record}
  alias Aether.ATProto.{CID, TID}

  # ============================================================================
  # Repository Management Endpoints
  # ============================================================================

  @doc """
  GET /xrpc/com.atproto.repo.describeRepo
  """
  def describe_repo(conn, %{"repo" => did}) do
    case Repositories.get_repository(did) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "RepoNotFound", message: "Repository not found"})

      %Repository{} = repo ->
        collections = Repositories.list_collections(did)

        response = %{
          did: repo.did,
          collections: collections,
          handle: did,
          didDoc: nil,
          handleIsCorrect: true
        }

        json(conn, response)
    end
  end

  # ============================================================================
  # Record Operations
  # ============================================================================

  @doc """
  GET /xrpc/com.atproto.repo.getRecord
  """
  def get_record(conn, %{"repo" => did, "collection" => collection, "rkey" => rkey}) do
    case Repositories.get_record(did, collection, rkey) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "RecordNotFound", message: "Record not found"})

      %Record{} = record ->
        response = %{
          uri: "at://#{did}/#{collection}/#{rkey}",
          cid: record.cid,
          value: record.value
        }

        json(conn, response)
    end
  end

  @doc """
  POST /xrpc/com.atproto.repo.createRecord
  """
  def create_record(conn, params) do
    %{
      "repo" => did,
      "collection" => collection,
      "record" => record_data
    } = params

    # Generate rkey if not provided
    rkey = Map.get(params, "rkey") || generate_tid()

    # Validate record doesn't exist
    if Repositories.record_exists?(did, collection, rkey) do
      conn
      |> put_status(:conflict)
      |> json(%{error: "RecordAlreadyExists", message: "Record already exists"})
    else
      # Calculate CID for the record
      record_cid = generate_cid(record_data)

      # Create the record
      record_attrs = %{
        repository_did: did,
        collection: collection,
        rkey: rkey,
        cid: record_cid,
        value: record_data
      }

      case create_record_with_commit(did, record_attrs, "create") do
        {:ok, record, commit} ->
          json(conn, %{
            uri: "at://#{did}/#{collection}/#{rkey}",
            cid: record.cid,
            commit: %{
              cid: commit.cid,
              rev: commit.rev
            }
          })

        {:error, reason} ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "InvalidRequest", message: inspect(reason)})
      end
    end
  end

  @doc """
  POST /xrpc/com.atproto.repo.putRecord
  """
  def put_record(conn, params) do
    %{
      "repo" => did,
      "collection" => collection,
      "rkey" => rkey,
      "record" => record_data
    } = params

    # Calculate CID for the record
    record_cid = generate_cid(record_data)

    case Repositories.get_record(did, collection, rkey) do
      nil ->
        # Create new record
        record_attrs = %{
          repository_did: did,
          collection: collection,
          rkey: rkey,
          cid: record_cid,
          value: record_data
        }

        case create_record_with_commit(did, record_attrs, "create") do
          {:ok, record, commit} ->
            json(conn, %{
              uri: "at://#{did}/#{collection}/#{rkey}",
              cid: record.cid,
              commit: %{cid: commit.cid, rev: commit.rev}
            })

          {:error, reason} ->
            conn
            |> put_status(:bad_request)
            |> json(%{error: "InvalidRequest", message: inspect(reason)})
        end

      %Record{} = existing_record ->
        # Update existing record
        update_attrs = %{
          cid: record_cid,
          value: record_data
        }

        case update_record_with_commit(did, existing_record, update_attrs) do
          {:ok, record, commit} ->
            json(conn, %{
              uri: "at://#{did}/#{collection}/#{rkey}",
              cid: record.cid,
              commit: %{cid: commit.cid, rev: commit.rev}
            })

          {:error, reason} ->
            conn
            |> put_status(:bad_request)
            |> json(%{error: "InvalidRequest", message: inspect(reason)})
        end
    end
  end

  @doc """
  POST /xrpc/com.atproto.repo.deleteRecord
  """
  def delete_record(conn, %{"repo" => did, "collection" => collection, "rkey" => rkey}) do
    case Repositories.get_record(did, collection, rkey) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "RecordNotFound", message: "Record not found"})

      %Record{} = record ->
        case delete_record_with_commit(did, record) do
          {:ok, commit} ->
            json(conn, %{
              commit: %{
                cid: commit.cid,
                rev: commit.rev
              }
            })

          {:error, reason} ->
            conn
            |> put_status(:bad_request)
            |> json(%{error: "InvalidRequest", message: inspect(reason)})
        end
    end
  end

  @doc """
  GET /xrpc/com.atproto.repo.listRecords
  """
  def list_records(conn, %{"repo" => did, "collection" => collection} = params) do
    limit = params |> Map.get("limit", "50") |> String.to_integer() |> min(100)
    cursor = Map.get(params, "cursor")
    reverse = Map.get(params, "reverse", "false") == "true"

    %{records: records, cursor: next_cursor} =
      Repositories.list_records(did, collection, limit: limit, cursor: cursor, reverse: reverse)

    formatted_records =
      Enum.map(records, fn record ->
        %{
          uri: "at://#{did}/#{collection}/#{record.rkey}",
          cid: record.cid,
          value: record.value
        }
      end)

    response = %{
      records: formatted_records
    }

    response = if next_cursor, do: Map.put(response, :cursor, next_cursor), else: response

    json(conn, response)
  end

  # ============================================================================
  # Helper Functions for Commit Logic
  # ============================================================================

  defp create_record_with_commit(did, record_attrs, action) do
    AetherPDSServer.Repo.transaction(fn ->
      # 1. Create the record
      {:ok, record} = Repositories.create_record(record_attrs)

      # 2. Build new MST with the record
      # TODO: Load existing MST, add record, get new root
      # For now, we'll create a simplified commit

      # 3. Create commit
      rev = generate_tid()
      repo = Repositories.get_repository!(did)

      commit_data = %{
        version: 3,
        did: did,
        rev: rev,
        prev: repo.head_cid,
        # Simplified - should be MST root
        data: record.cid
      }

      commit_cid = generate_cid(commit_data)

      commit_attrs = %{
        repository_did: did,
        cid: commit_cid,
        rev: rev,
        prev: repo.head_cid,
        data: commit_data
      }

      {:ok, commit} = Repositories.create_commit(commit_attrs)

      # 4. Update repository HEAD
      {:ok, _repo} = Repositories.update_repository(repo, %{head_cid: commit_cid})

      # 5. Create event
      event_attrs = %{
        repository_did: did,
        commit_cid: commit_cid,
        rev: rev,
        ops: [
          %{
            action: action,
            path: "#{record.collection}/#{record.rkey}",
            cid: record.cid
          }
        ],
        time: DateTime.utc_now()
      }

      {:ok, _event} = Repositories.create_event(event_attrs)

      {record, commit}
    end)
  end

  defp update_record_with_commit(did, record, update_attrs) do
    AetherPDSServer.Repo.transaction(fn ->
      {:ok, updated_record} = Repositories.update_record(record, update_attrs)

      # Create commit (similar to create)
      rev = generate_tid()
      repo = Repositories.get_repository!(did)

      commit_data = %{
        version: 3,
        did: did,
        rev: rev,
        prev: repo.head_cid,
        data: updated_record.cid
      }

      commit_cid = generate_cid(commit_data)

      commit_attrs = %{
        repository_did: did,
        cid: commit_cid,
        rev: rev,
        prev: repo.head_cid,
        data: commit_data
      }

      {:ok, commit} = Repositories.create_commit(commit_attrs)
      {:ok, _repo} = Repositories.update_repository(repo, %{head_cid: commit_cid})

      event_attrs = %{
        repository_did: did,
        commit_cid: commit_cid,
        rev: rev,
        ops: [
          %{
            action: "update",
            path: "#{updated_record.collection}/#{updated_record.rkey}",
            cid: updated_record.cid
          }
        ],
        time: DateTime.utc_now()
      }

      {:ok, _event} = Repositories.create_event(event_attrs)

      {updated_record, commit}
    end)
  end

  defp delete_record_with_commit(did, record) do
    AetherPDSServer.Repo.transaction(fn ->
      {:ok, _deleted} = Repositories.delete_record(record)

      rev = generate_tid()
      repo = Repositories.get_repository!(did)

      commit_data = %{
        version: 3,
        did: did,
        rev: rev,
        prev: repo.head_cid,
        data: nil
      }

      commit_cid = generate_cid(commit_data)

      commit_attrs = %{
        repository_did: did,
        cid: commit_cid,
        rev: rev,
        prev: repo.head_cid,
        data: commit_data
      }

      {:ok, commit} = Repositories.create_commit(commit_attrs)
      {:ok, _repo} = Repositories.update_repository(repo, %{head_cid: commit_cid})

      event_attrs = %{
        repository_did: did,
        commit_cid: commit_cid,
        rev: rev,
        ops: [
          %{
            action: "delete",
            path: "#{record.collection}/#{record.rkey}",
            cid: nil
          }
        ],
        time: DateTime.utc_now()
      }

      {:ok, _event} = Repositories.create_event(event_attrs)

      commit
    end)
  end

  defp generate_cid(data) when is_map(data) do
    # Create a proper CID using your library
    hash = :crypto.hash(:sha256, Jason.encode!(data))
    encoded = Base.encode32(hash, case: :lower, padding: false)
    cid_string = "bafyrei" <> String.slice(encoded, 0..50)

    # Parse and validate it as a CID
    case CID.parse_cid(cid_string) do
      {:ok, cid} -> CID.cid_to_string(cid)
      # Fallback to raw string
      {:error, _} -> cid_string
    end
  end

  defp generate_tid do
    TID.new()
  end
end
