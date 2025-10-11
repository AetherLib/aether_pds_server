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
    # NOTE: We need updated_conn for proper connection state
    case MinioStorage.upload_blob(conn, did, mime_type) do
      {:ok, updated_conn, cid, size, storage_key} ->
        Logger.info("MinIO upload successful - CID: #{cid}, Size: #{size}, Storage: #{storage_key}")

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
            # IMPORTANT: Key order matters for Bluesky's parser
            # Must match official PDS response format exactly
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

            Logger.info("Blob upload success - sending response with original conn")

            # Encode JSON and send with explicit content-length
            # Bluesky client requires exact byte-perfect response
            json_body = Jason.encode!(response)
            content_length = byte_size(json_body)

            Logger.info("Sending response - body size: #{content_length} bytes")
            Logger.info("Response JSON: #{json_body}")
            Logger.info("Response bytes (hex): #{Base.encode16(json_body)}")

            # Use original conn and register a callback to ensure response is sent
            conn
            |> register_before_send(fn conn ->
              Logger.info("Before send callback - ensuring response is flushed")
              conn
            end)
            |> delete_resp_header("content-type")
            |> put_resp_header("content-type", "application/json; charset=utf-8")
            |> put_resp_header("content-length", Integer.to_string(content_length))
            |> send_resp(200, json_body)

          {:error, changeset} ->
            Logger.error("Failed to save blob metadata: #{inspect(changeset)}")
            json(conn, %{error: "BlobMetadataFailed", message: "Failed to save metadata"})
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
end
