defmodule AetherPDSServerWeb.RepoController do
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
      mst_root_cid_string = CID.cid_to_string(mst_root_cid)

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

      commit_cbor = Commit.to_cbor(commit)
      commit_cid_string = CID.from_data(commit_cbor, "dag-cbor")

      commit_attrs = %{
        repository_did: repo_did,
        cid: commit_cid_string,
        rev: rev,
        prev: repo.head_cid,
        data: %{
          version: 3,
          did: repo_did,
          rev: rev,
          data: mst_root_cid_string,
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

  # Process update (without committing)
  defp process_update(repo_did, write, mst) do
    collection = write["collection"]
    rkey = write["rkey"]
    value = write["value"]

    case Repositories.get_record(repo_did, collection, rkey) do
      nil ->
        result = %{
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

  # Process delete (without committing)
  defp process_delete(repo_did, write, mst) do
    collection = write["collection"]
    rkey = write["rkey"]

    case Repositories.get_record(repo_did, collection, rkey) do
      nil ->
        result = %{
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
      mst_root_cid_string = CID.cid_to_string(mst_root_cid)

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
          data: mst_root_cid_string,
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
      mst_root_cid_string = CID.cid_to_string(mst_root_cid)

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
          data: mst_root_cid_string,
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
      mst_root_cid_string = CID.cid_to_string(mst_root_cid)

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
          data: mst_root_cid_string,
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
    # Serialize MST to CBOR-like format
    mst_data = serialize_mst(mst)

    # Calculate CID for the MST
    hash = :crypto.hash(:sha256, mst_data)
    hash_encoded = Base.encode32(hash, case: :lower, padding: false)
    cid_string = "bafyrei" <> String.slice(hash_encoded, 0..50)

    {:ok, mst_cid} =
      case CID.parse_cid(cid_string) do
        {:ok, cid} -> {:ok, cid}
        {:error, _} -> {:ok, CID.new(1, "dag-cbor", cid_string)}
      end

    # Store MST block in repository
    mst_blocks = %{cid_string => mst_data}
    Repositories.put_mst_blocks(did, mst_blocks)

    mst_cid
  end

  defp serialize_mst(mst) do
    # Serialize MST entries to binary
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
end
