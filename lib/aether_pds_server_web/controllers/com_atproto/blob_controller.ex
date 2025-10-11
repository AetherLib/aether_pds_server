# lib/aether_pds_server_web/controllers/blob_controller.ex
defmodule AetherPDSServerWeb.ComATProto.BlobController do
  use AetherPDSServerWeb, :controller

  alias AetherPDSServer.Repositories
  alias AetherPDSServer.MinioStorage

  require Logger

  @doc """
  POST /xrpc/com.atproto.repo.uploadBlob

  Upload a blob (image, video, etc.) by streaming to MinIO.
  Never loads full blob into memory.
  """
  def upload_blob(conn, _params) do
    did = conn.assigns[:current_did]
    mime_type = get_content_type(conn)

    # Stream upload to MinIO while calculating CID
    case MinioStorage.upload_blob(conn, did, mime_type) do
      {:ok, updated_conn, cid, size, storage_key} ->
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
            response = %{
              blob: %{
                "$type" => "blob",
                ref: %{
                  "$link" => cid
                },
                mimeType: mime_type,
                size: size
              }
            }

            # Log the exact response being sent
            response_json = Jason.encode!(response)
            content_length = byte_size(response_json)
            Logger.info("Sending blob upload response: #{response_json} (#{content_length} bytes)")

            updated_conn
            |> put_resp_content_type("application/json")
            |> put_resp_header("content-length", Integer.to_string(content_length))
            |> send_resp(200, response_json)
            |> halt()

          {:error, changeset} ->
            Logger.error("Failed to save blob metadata: #{inspect(changeset)}")

            conn
            |> put_status(:internal_server_error)
            |> json(%{
              error: "BlobMetadataFailed",
              message: "Blob uploaded to storage but failed to save metadata"
            })
        end

      {:error, reason} ->
        Logger.error("Failed to upload blob: #{inspect(reason)}")

        conn
        |> put_status(:bad_request)
        |> json(%{error: "BlobUploadFailed", message: "Failed to upload blob to storage"})
    end
  end

  defp get_content_type(conn) do
    case get_req_header(conn, "content-type") do
      [content_type | _] -> content_type
      [] -> "application/octet-stream"
    end
  end
end
