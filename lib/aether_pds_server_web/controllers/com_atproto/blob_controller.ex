defmodule AetherPDSServerWeb.ComATProto.BlobController do
  use AetherPDSServerWeb, :controller

  alias AetherPDSServer.Repositories
  alias AetherPDSServer.MinioStorage

  require Logger

  @doc """
  POST /xrpc/com.atproto.repo.uploadBlob

  Upload a blob (image, video, etc.) by streaming to MinIO.
  """
  def upload_blob(conn, _params) do
    did = conn.assigns[:current_did]
    mime_type = get_content_type(conn)

    # Stream upload to MinIO while calculating CID
    case MinioStorage.upload_blob(conn, did, mime_type) do
      {:ok, _updated_conn, cid, size, storage_key} ->
        # Logger.info("MinIO upload successful - CID: #{cid}, Size: #{size}, Storage: #{storage_key}")

        # Store metadata in database
        blob_attrs = %{
          repository_did: did,
          cid: cid,
          mime_type: mime_type,
          size: size,
          storage_key: storage_key
        }

        case Repositories.create_blob(blob_attrs) do
          {:ok, _blob} ->
            # Blob created successfully
            send_blob_response(conn, cid, mime_type, size)

          {:error, %Ecto.Changeset{errors: errors} = changeset} ->
            # Check if error is due to duplicate blob (already exists)
            case Keyword.get(errors, :repository_did) do
              {"has already been taken", _} ->
                # Blob already exists - this is fine, return success
                # Logger.info("Blob already exists - CID: #{cid}")
                send_blob_response(conn, cid, mime_type, size)

              _ ->
                # Some other error
                Logger.error("Failed to save blob metadata: #{inspect(changeset)}")

                conn
                |> put_status(:internal_server_error)
                |> json(%{error: "BlobMetadataFailed", message: "Failed to save metadata"})
            end
        end

      {:error, reason} ->
        Logger.error("Failed to upload blob: #{inspect(reason)}")
        json(conn, %{error: "BlobUploadFailed", message: "Failed to upload"})
    end
  end

  defp get_content_type(conn) do
    case get_req_header(conn, "content-type") do
      [content_type | _] -> content_type
      [] -> "application/octet-stream"
    end
  end

  defp send_blob_response(conn, cid, mime_type, size) do
    response = %{
      blob: %{
        "$type" => "blob",
        "ref" => %{
          "$link" => cid
        },
        "mimeType" => mime_type,
        "size" => size
      }
    }

    # Logger.info("Blob upload success - CID: #{cid}")
    json_body = Jason.encode!(response)
    content_length = byte_size(json_body)

    conn
    |> register_before_send(fn conn ->
      # Logger.info("Before send callback - ensuring response is flushed")
      conn
    end)
    |> delete_resp_header("content-type")
    |> put_resp_header("content-type", "application/json; charset=utf-8")
    |> put_resp_header("content-length", Integer.to_string(content_length))
    |> send_resp(200, json_body)
  end
end
