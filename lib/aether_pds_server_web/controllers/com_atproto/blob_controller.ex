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

            Logger.info("Blob upload success - DID: #{did}, CID: #{cid}, Size: #{size}")
            Logger.info("Sending response: #{inspect(response)}")
            Logger.info("Original conn state: #{inspect(conn.state)}, body_params: #{inspect(conn.body_params)}")
            Logger.info("Updated conn state: #{inspect(updated_conn.state)}, body_params: #{inspect(updated_conn.body_params)}")

            # CRITICAL: Use the ORIGINAL conn, not updated_conn
            # After reading the body with Plug.Conn.read_body, the updated_conn
            # may be in a state that prevents proper response sending through proxies
            result = json(conn, response)
            Logger.info("After json/2 - state: #{inspect(result.state)}, resp_body length: #{inspect(byte_size(result.resp_body || ""))}")
            result

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
