defmodule AetherPDSServerWeb.ComATProto.RepoController do
  @moduledoc """
  XRPC Controller for ATProto Repository Operations
  """
  use AetherPDSServerWeb, :controller

  alias AetherPDSServer.Repositories
  alias AetherPDSServer.Repositories.{Repository, Record}
  alias Aether.ATProto.{CID, TID, MST, Commit}

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
    current_did = conn.assigns[:current_did]

    %{
      "repo" => did,
      "collection" => collection,
      "record" => record_data
    } = params

    # Verify the user owns this repository
    if did != current_did do
      conn
      |> put_status(:forbidden)
      |> json(%{error: "Forbidden", message: "Cannot write to another user's repository"})
    else
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
          {:ok, {record, commit}} ->
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
  end

  @doc """
  POST /xrpc/com.atproto.repo.putRecord
  """
  def put_record(conn, params) do
    current_did = conn.assigns[:current_did]

    %{
      "repo" => did,
      "collection" => collection,
      "rkey" => rkey,
      "record" => record_data
    } = params

    # Verify the user owns this repository
    if did != current_did do
      conn
      |> put_status(:forbidden)
      |> json(%{error: "Forbidden", message: "Cannot write to another user's repository"})
    else
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
            {:ok, {record, commit}} ->
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
            {:ok, {record, commit}} ->
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
  end

  @doc """
  POST /xrpc/com.atproto.repo.deleteRecord
  """
  def delete_record(conn, %{"repo" => did, "collection" => collection, "rkey" => rkey}) do
    current_did = conn.assigns[:current_did]

    # Verify the user owns this repository
    if did != current_did do
      conn
      |> put_status(:forbidden)
      |> json(%{error: "Forbidden", message: "Cannot write to another user's repository"})
    else
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

  @doc """
  GET /xrpc/com.atproto.repo.listMissingBlobs

  List blobs that are referenced in records but missing from storage.
  """
  def list_missing_blobs(conn, %{"repo" => did} = params) do
    # For now, we return an empty list as we don't track missing blobs
    # In a production system, this would:
    # 1. Scan all records for blob references
    # 2. Check if each referenced blob exists in storage
    # 3. Return CIDs of missing blobs

    limit = params |> Map.get("limit", "500") |> String.to_integer() |> min(1000)
    _cursor = Map.get(params, "cursor")

    # Verify repository exists
    case Repositories.get_repository(did) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "RepoNotFound", message: "Repository not found"})

      _repo ->
        # Return empty list (no missing blobs detected)
        response = %{
          blobs: []
        }

        json(conn, response)
    end
  end

  @doc """
  POST /xrpc/com.atproto.repo.importRepo

  Import a repository from a CAR file.
  This completely replaces the repository contents with the imported data.
  """
  def import_repo(conn, _params) do
    current_did = conn.assigns[:current_did]

    # Read the CAR file from request body
    {:ok, car_binary, _conn} = Plug.Conn.read_body(conn)

    case import_repo_from_car(current_did, car_binary) do
      :ok ->
        json(conn, %{})

      {:error, :invalid_car} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "InvalidRequest", message: "Invalid CAR file format"})

      {:error, :repository_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "RepoNotFound", message: "Repository not found"})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "ImportFailed", message: "Failed to import repository: #{inspect(reason)}"})
    end
  end

  @doc """
  POST /xrpc/com.atproto.repo.applyWrites

  Apply a batch of write operations (creates, updates, deletes) to a repository.
  All operations are applied atomically.
  """
  def apply_writes(conn, %{"repo" => repo, "writes" => writes} = params) do
    current_did = conn.assigns[:current_did]

    # Verify the user owns this repository
    if repo != current_did do
      conn
      |> put_status(:forbidden)
      |> json(%{error: "Forbidden", message: "Cannot write to another user's repository"})
    else
      # Validate the repo exists
      case Repositories.get_repository(repo) do
        nil ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "RepoNotFound", message: "Repository not found"})

        _repository ->
          # Validate optional parameters
          validate = Map.get(params, "validate", true)
          swap_commit = Map.get(params, "swapCommit")

          # Apply writes in a transaction
          case apply_batch_writes(repo, writes, validate, swap_commit) do
            {:ok, {results, commit}} ->
              json(conn, %{
                commit: %{
                  cid: commit.cid,
                  rev: commit.rev
                },
                results: results
              })

            {:error, reason} ->
              conn
              |> put_status(:bad_request)
              |> json(%{error: "InvalidRequest", message: inspect(reason)})
          end
      end
    end
  end

  # ============================================================================
  # Batch Write Operations
  # ============================================================================

  # Apply batch writes atomically with a single commit
  defp apply_batch_writes(repo_did, writes, _validate, _swap_commit) do
    AetherPDSServer.Repo.transaction(fn ->
      # Load current repository and MST
      repo = Repositories.get_repository!(repo_did)
      {:ok, mst} = load_mst(repo_did)

      # Process each write and build results
      {results, updated_mst, ops} =
        Enum.reduce(writes, {[], mst, []}, fn write, {acc_results, acc_mst, acc_ops} ->
          case write["$type"] do
            "com.atproto.repo.applyWrites#create" ->
              {result, new_mst, op} = process_create(repo_did, write, acc_mst)
              {[result | acc_results], new_mst, [op | acc_ops]}

            "com.atproto.repo.applyWrites#update" ->
              {result, new_mst, op} = process_update(repo_did, write, acc_mst)
              {[result | acc_results], new_mst, [op | acc_ops]}

            "com.atproto.repo.applyWrites#delete" ->
              {result, new_mst, op} = process_delete(repo_did, write, acc_mst)
              {[result | acc_results], new_mst, [op | acc_ops]}

            unknown_type ->
              AetherPDSServer.Repo.rollback({:unknown_write_type, unknown_type})
          end
        end)

      # Create a single commit for all operations
      mst_root_cid = store_mst(repo_did, updated_mst)

      rev = generate_tid()

      prev_cid =
        if repo.head_cid do
          case CID.parse_cid(repo.head_cid) do
            {:ok, cid} -> cid
            _ -> nil
          end
        else
          nil
        end

      commit = Commit.create(repo_did, mst_root_cid, rev: rev, prev: prev_cid)

      # Generate proper commit CID using the updated Commit.cid/1
      commit_cid = Commit.cid(commit)
      commit_cid_string = CID.cid_to_string(commit_cid)

      commit_attrs = %{
        repository_did: repo_did,
        cid: commit_cid_string,
        rev: rev,
        prev: repo.head_cid,
        data: %{
          version: 3,
          did: repo_did,
          rev: rev,
          data: CID.cid_to_string(mst_root_cid),
          prev: repo.head_cid
        }
      }

      {:ok, commit_record} = Repositories.create_commit(commit_attrs)
      {:ok, _repo} = Repositories.update_repository(repo, %{head_cid: commit_cid_string})

      # Create event with all operations
      event_attrs = %{
        repository_did: repo_did,
        commit_cid: commit_cid_string,
        rev: rev,
        ops: Enum.reverse(ops),
        time: DateTime.utc_now()
      }

      {:ok, _event} = Repositories.create_event(event_attrs)

      # Return results and commit info
      {Enum.reverse(results), commit_record}
    end)
  end

  defp process_create(repo_did, write, mst) do
    collection = write["collection"]
    rkey = write["rkey"] || generate_tid()
    value = write["value"]

    # Check if record already exists
    if Repositories.record_exists?(repo_did, collection, rkey) do
      result = %{
        "$type" => "com.atproto.repo.applyWrites#createResult",
        "uri" => "at://#{repo_did}/#{collection}/#{rkey}",
        "cid" => nil,
        "validationStatus" => "invalid"
      }

      op = nil
      {result, mst, op}
    else
      # Calculate CID
      record_cid = generate_cid(value)

      record_attrs = %{
        repository_did: repo_did,
        collection: collection,
        rkey: rkey,
        cid: record_cid,
        value: value
      }

      case Repositories.create_record(record_attrs) do
        {:ok, record} ->
          # Update MST
          {:ok, record_cid_parsed} = CID.parse_cid(record.cid)
          mst_key = "#{collection}/#{rkey}"
          {:ok, updated_mst} = MST.add(mst, mst_key, record_cid_parsed)

          result = %{
            "$type" => "com.atproto.repo.applyWrites#createResult",
            "uri" => "at://#{repo_did}/#{collection}/#{rkey}",
            "cid" => record.cid,
            "validationStatus" => "valid"
          }

          op = %{
            action: "create",
            path: "#{collection}/#{rkey}",
            cid: record.cid
          }

          {result, updated_mst, op}

        {:error, _changeset} ->
          AetherPDSServer.Repo.rollback(:create_failed)
      end
    end
  end

  defp process_update(repo_did, write, mst) do
    collection = write["collection"]
    rkey = write["rkey"]
    value = write["value"]

    case Repositories.get_record(repo_did, collection, rkey) do
      nil ->
        result = %{
          "$type" => "com.atproto.repo.applyWrites#updateResult",
          "uri" => "at://#{repo_did}/#{collection}/#{rkey}",
          "cid" => nil,
          "validationStatus" => "invalid"
        }

        {result, mst, nil}

      existing_record ->
        # Calculate new CID
        new_cid = generate_cid(value)

        case Repositories.update_record(existing_record, %{cid: new_cid, value: value}) do
          {:ok, updated_record} ->
            # Update MST
            {:ok, record_cid_parsed} = CID.parse_cid(updated_record.cid)
            mst_key = "#{collection}/#{rkey}"
            {:ok, updated_mst} = MST.add(mst, mst_key, record_cid_parsed)

            result = %{
              "$type" => "com.atproto.repo.applyWrites#updateResult",
              "uri" => "at://#{repo_did}/#{collection}/#{rkey}",
              "cid" => updated_record.cid,
              "validationStatus" => "valid"
            }

            op = %{
              action: "update",
              path: "#{collection}/#{rkey}",
              cid: updated_record.cid
            }

            {result, updated_mst, op}

          {:error, _changeset} ->
            AetherPDSServer.Repo.rollback(:update_failed)
        end
    end
  end

  defp process_delete(repo_did, write, mst) do
    collection = write["collection"]
    rkey = write["rkey"]

    case Repositories.get_record(repo_did, collection, rkey) do
      nil ->
        result = %{
          "$type" => "com.atproto.repo.applyWrites#deleteResult",
          "validationStatus" => "invalid"
        }

        {result, mst, nil}

      record ->
        case Repositories.delete_record(record) do
          {:ok, _deleted} ->
            # Update MST
            mst_key = "#{collection}/#{rkey}"

            updated_mst =
              case MST.delete(mst, mst_key) do
                {:ok, updated} -> updated
                {:error, :not_found} -> mst
              end

            result = %{
              "$type" => "com.atproto.repo.applyWrites#deleteResult",
              "validationStatus" => "valid"
            }

            op = %{
              action: "delete",
              path: "#{collection}/#{rkey}",
              cid: nil
            }

            {result, updated_mst, op}

          {:error, _changeset} ->
            AetherPDSServer.Repo.rollback(:delete_failed)
        end
    end
  end

  # ============================================================================
  # Helper Functions for Commit Logic
  # ============================================================================

  defp create_record_with_commit(did, record_attrs, action) do
    AetherPDSServer.Repo.transaction(fn ->
      # 1. Create the record
      {:ok, record} = Repositories.create_record(record_attrs)

      # 2. Load current MST and add the new record
      repo = Repositories.get_repository!(did)
      {:ok, mst} = load_mst(did)

      # Parse the record CID
      {:ok, record_cid} = CID.parse_cid(record.cid)

      # Add record to MST (key is collection/rkey)
      mst_key = "#{record.collection}/#{record.rkey}"
      {:ok, updated_mst} = MST.add(mst, mst_key, record_cid)

      # 3. Store updated MST and get root CID
      mst_root_cid = store_mst(did, updated_mst)

      # 4. Create commit pointing to new MST root
      rev = generate_tid()

      prev_cid =
        if repo.head_cid do
          case CID.parse_cid(repo.head_cid) do
            {:ok, cid} -> cid
            _ -> nil
          end
        else
          nil
        end

      commit = Commit.create(did, mst_root_cid, rev: rev, prev: prev_cid)

      # Use the updated Commit.cid/1 which now generates proper CIDs
      commit_cid = Commit.cid(commit)
      commit_cid_string = CID.cid_to_string(commit_cid)

      commit_attrs = %{
        repository_did: did,
        cid: commit_cid_string,
        rev: rev,
        prev: repo.head_cid,
        data: %{
          version: 3,
          did: did,
          rev: rev,
          data: CID.cid_to_string(mst_root_cid),
          prev: repo.head_cid
        }
      }

      {:ok, commit_record} = Repositories.create_commit(commit_attrs)

      # 5. Update repository HEAD
      {:ok, _repo} = Repositories.update_repository(repo, %{head_cid: commit_cid_string})

      # 6. Create event
      event_attrs = %{
        repository_did: did,
        commit_cid: commit_cid_string,
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

      {record, commit_record}
    end)
  end

  defp update_record_with_commit(did, record, update_attrs) do
    AetherPDSServer.Repo.transaction(fn ->
      {:ok, updated_record} = Repositories.update_record(record, update_attrs)

      # Load current MST and update the record
      repo = Repositories.get_repository!(did)
      {:ok, mst} = load_mst(did)

      # Parse the updated record CID
      {:ok, record_cid} = CID.parse_cid(updated_record.cid)

      # Update record in MST (this is the same as add)
      mst_key = "#{updated_record.collection}/#{updated_record.rkey}"
      {:ok, updated_mst} = MST.add(mst, mst_key, record_cid)

      # Store updated MST
      mst_root_cid = store_mst(did, updated_mst)

      # Create commit
      rev = generate_tid()

      prev_cid =
        if repo.head_cid do
          case CID.parse_cid(repo.head_cid) do
            {:ok, cid} -> cid
            _ -> nil
          end
        else
          nil
        end

      commit = Commit.create(did, mst_root_cid, rev: rev, prev: prev_cid)

      # Use the updated Commit.cid/1
      commit_cid = Commit.cid(commit)
      commit_cid_string = CID.cid_to_string(commit_cid)

      commit_attrs = %{
        repository_did: did,
        cid: commit_cid_string,
        rev: rev,
        prev: repo.head_cid,
        data: %{
          version: 3,
          did: did,
          rev: rev,
          data: CID.cid_to_string(mst_root_cid),
          prev: repo.head_cid
        }
      }

      {:ok, commit_record} = Repositories.create_commit(commit_attrs)
      {:ok, _repo} = Repositories.update_repository(repo, %{head_cid: commit_cid_string})

      event_attrs = %{
        repository_did: did,
        commit_cid: commit_cid_string,
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

      {updated_record, commit_record}
    end)
  end

  defp delete_record_with_commit(did, record) do
    AetherPDSServer.Repo.transaction(fn ->
      # Load current MST and remove the record BEFORE deleting from DB
      repo = Repositories.get_repository!(did)
      {:ok, mst} = load_mst(did)

      # Delete record from MST
      mst_key = "#{record.collection}/#{record.rkey}"

      updated_mst =
        case MST.delete(mst, mst_key) do
          {:ok, updated} -> updated
          {:error, :not_found} -> mst
        end

      # Now delete from database
      {:ok, _deleted} = Repositories.delete_record(record)

      # Store updated MST
      mst_root_cid = store_mst(did, updated_mst)

      # Create commit
      rev = generate_tid()

      prev_cid =
        if repo.head_cid do
          case CID.parse_cid(repo.head_cid) do
            {:ok, cid} -> cid
            _ -> nil
          end
        else
          nil
        end

      commit = Commit.create(did, mst_root_cid, rev: rev, prev: prev_cid)

      # Use the updated Commit.cid/1
      commit_cid = Commit.cid(commit)
      commit_cid_string = CID.cid_to_string(commit_cid)

      commit_attrs = %{
        repository_did: did,
        cid: commit_cid_string,
        rev: rev,
        prev: repo.head_cid,
        data: %{
          version: 3,
          did: did,
          rev: rev,
          data: CID.cid_to_string(mst_root_cid),
          prev: repo.head_cid
        }
      }

      {:ok, commit_record} = Repositories.create_commit(commit_attrs)
      {:ok, _repo} = Repositories.update_repository(repo, %{head_cid: commit_cid_string})

      event_attrs = %{
        repository_did: did,
        commit_cid: commit_cid_string,
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

      commit_record
    end)
  end

  # Use CID.from_map for consistent CID generation
  defp generate_cid(data) when is_map(data) do
    CID.from_map(data)
  end

  defp generate_tid do
    TID.new()
  end

  # ============================================================================
  # MST Helper Functions
  # ============================================================================

  defp load_mst(did) do
    # Get all records for this repository and rebuild MST
    records = Repositories.list_records(did, "*", limit: 10000)

    mst = %MST{}

    # Add all existing records to MST
    mst =
      Enum.reduce(records.records, mst, fn record, acc_mst ->
        case CID.parse_cid(record.cid) do
          {:ok, record_cid} ->
            mst_key = "#{record.collection}/#{record.rkey}"
            {:ok, updated_mst} = MST.add(acc_mst, mst_key, record_cid)
            updated_mst

          {:error, _} ->
            acc_mst
        end
      end)

    {:ok, mst}
  end

  defp store_mst(did, mst) do
    # Serialize MST to CBOR
    mst_data = serialize_mst(mst)

    # Generate proper CIDv1 using CID.from_data
    cid_string = CID.from_data(mst_data, "dag-cbor")
    {:ok, mst_cid} = CID.parse_cid(cid_string)

    # Store MST block in repository
    mst_blocks = %{cid_string => mst_data}
    Repositories.put_mst_blocks(did, mst_blocks)

    mst_cid
  end

  defp serialize_mst(mst) do
    # Serialize MST entries to CBOR
    entries_data =
      Enum.map(mst.entries, fn entry ->
        %{
          key: entry.key,
          value: CID.cid_to_string(entry.value)
        }
      end)

    # Use CBOR encoding
    CBOR.encode(%{
      layer: mst.layer,
      entries: entries_data
    })
  end

  # ============================================================================
  # CAR Import Helpers
  # ============================================================================

  defp import_repo_from_car(did, car_binary) when is_binary(car_binary) do
    alias Aether.ATProto.CAR

    # Verify repository exists
    repo = Repositories.get_repository(did)

    if repo == nil do
      {:error, :repository_not_found}
    else
      # Parse CAR file
      case CAR.decode(car_binary) do
        {:ok, car} ->
          # Validate CAR has exactly one root (the commit CID)
          if length(car.roots) != 1 do
            {:error, :invalid_car}
          else
            # Process import in a transaction
            AetherPDSServer.Repo.transaction(fn ->
              process_car_import(did, car)
            end)

            :ok
          end

        {:error, _reason} ->
          {:error, :invalid_car}
      end
    end
  end

  defp import_repo_from_car(_did, _invalid), do: {:error, :invalid_car}

  defp process_car_import(did, car) do
    alias Aether.ATProto.CAR

    [root_cid] = car.roots
    root_cid_string = CID.cid_to_string(root_cid)

    # 1. Find the commit block
    {:ok, commit_block} = CAR.get_block(car, root_cid)

    # 2. Parse commit data
    {:ok, commit_data, ""} = CBOR.decode(commit_block.data)

    # Extract MST root CID from commit
    mst_root_cid_string = commit_data["data"]
    {:ok, mst_root_cid} = CID.parse_cid(mst_root_cid_string)

    # 3. Clear existing repository data
    clear_repository_data(did)

    # 4. Import all blocks (MST blocks and record blocks)
    import_blocks(did, car)

    # 5. Rebuild records from MST
    import_records_from_mst(did, car, mst_root_cid)

    # 6. Create new commit
    rev = commit_data["rev"] || generate_tid()

    commit_attrs = %{
      repository_did: did,
      cid: root_cid_string,
      rev: rev,
      prev: commit_data["prev"],
      data: commit_data
    }

    {:ok, _commit} = Repositories.create_commit(commit_attrs)

    # 7. Update repository head
    {:ok, repo} = Repositories.get_repository(did) |> Repositories.update_repository(%{head_cid: root_cid_string})

    # 8. Create import event
    event_attrs = %{
      repository_did: did,
      commit_cid: root_cid_string,
      rev: rev,
      ops: [%{action: "import", path: "*", cid: nil}],
      time: DateTime.utc_now()
    }

    {:ok, _event} = Repositories.create_event(event_attrs)

    :ok
  end

  defp clear_repository_data(did) do
    # Delete all existing records
    collections = Repositories.list_collections(did)

    Enum.each(collections, fn collection ->
      result = Repositories.list_records(did, collection, limit: 10000)

      Enum.each(result.records, fn record ->
        Repositories.delete_record(record)
      end)
    end)

    # Note: We keep commits and events for audit purposes
    # In a production system, you might want to archive them instead
  end

  defp import_blocks(did, car) do
    alias Aether.ATProto.CAR

    # Store all MST blocks
    mst_blocks =
      car.blocks
      |> Enum.map(fn block ->
        cid_string = CID.cid_to_string(block.cid)
        {cid_string, block.data}
      end)
      |> Enum.into(%{})

    Repositories.put_mst_blocks(did, mst_blocks)
  end

  defp import_records_from_mst(did, car, mst_root_cid) do
    alias Aether.ATProto.CAR

    # Get the MST root block
    {:ok, mst_block} = CAR.get_block(car, mst_root_cid)

    # Parse MST structure
    {:ok, mst_data, ""} = CBOR.decode(mst_block.data)

    # Extract entries from MST
    entries = mst_data["entries"] || []

    # Import each record
    Enum.each(entries, fn entry ->
      # Entry format: %{"key" => "collection/rkey", "value" => "cid_string"}
      key = entry["key"]
      record_cid_string = entry["value"]

      # Parse collection and rkey from key
      case String.split(key, "/", parts: 2) do
        [collection, rkey] ->
          # Get the record block
          {:ok, record_cid} = CID.parse_cid(record_cid_string)
          {:ok, record_block} = CAR.get_block(car, record_cid)

          # Parse record value
          {:ok, record_value, ""} = CBOR.decode(record_block.data)

          # Create record
          record_attrs = %{
            repository_did: did,
            collection: collection,
            rkey: rkey,
            cid: record_cid_string,
            value: record_value
          }

          Repositories.create_record(record_attrs)

        _ ->
          # Invalid key format, skip
          :ok
      end
    end)
  end
end
