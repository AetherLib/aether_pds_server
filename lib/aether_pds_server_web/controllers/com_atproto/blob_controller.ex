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

    # TEST: Return immediate response without consuming body
    test_response = %{
      blob: %{
        "$type" => "blob",
        ref: %{
          "$link" => "bafkreitest123"
        },
        mimeType: mime_type,
        size: 12345
      }
    }

    Logger.info("TEST MODE: Returning response without consuming body")
    json(conn, test_response)

    # # Stream upload to MinIO while calculating CID
    # case MinioStorage.upload_blob(conn, did, mime_type) do
    #   {:ok, updated_conn, cid, size, storage_key} ->
    #     Logger.info("MinIO upload successful - CID: #{cid}, Size: #{size}, Storage: #{storage_key}")

    #     # Store metadata in database
    #     blob_attrs = %{
    #       repository_did: did,
    #       cid: cid,
    #       mime_type: mime_type,
    #       size: size,
    #       storage_key: storage_key
    #     }

    #     case Repositories.create_blob(blob_attrs) do
    #       {:ok, _blob} ->
    #         response = %{
    #           blob: %{
    #             "$type" => "blob",
    #             ref: %{
    #               "$link" => cid
    #             },
    #             mimeType: mime_type,
    #             size: size
    #           }
    #         }

    #         Logger.info("Blob upload success - DID: #{did}, CID: #{cid}, Size: #{size}")

    #         # Encode response
    #         json_body = Jason.encode!(response)
    #         Logger.info("Encoded JSON body: #{json_body} (#{byte_size(json_body)} bytes)")

    #         # Try using Plug.Conn.inform to send an early hint, then regular response
    #         # This might help with HTTP/2 state issues
    #         try do
    #           result =
    #             conn
    #             |> delete_resp_header("transfer-encoding")
    #             |> put_resp_content_type("application/json; charset=utf-8")
    #             |> put_resp_header("content-length", Integer.to_string(byte_size(json_body)))
    #             |> resp(200, json_body)

    #           # Force the response to be sent
    #           {:ok, sent_conn} = Plug.Conn.Adapter.send_resp(result.adapter, result.status, result.resp_headers, result.resp_body)
    #           Logger.info("Response sent via adapter - sent successfully")
    #           %{result | adapter: sent_conn, state: :sent}
    #         rescue
    #           e ->
    #             Logger.error("Failed to send response: #{inspect(e)}")
    #             conn |> send_resp(500, Jason.encode!(%{error: "Internal server error"}))
    #         end

    #       {:error, changeset} ->
    #         Logger.error("Failed to save blob metadata: #{inspect(changeset)}")

    #         conn
    #         |> put_status(:internal_server_error)
    #         |> json(%{
    #           error: "BlobMetadataFailed",
    #           message: "Blob uploaded to storage but failed to save metadata"
    #         })
    #     end

    #   {:error, reason} ->
    #     Logger.error("Failed to upload blob: #{inspect(reason)}")

    #     conn
    #     |> put_status(:bad_request)
    #     |> json(%{error: "BlobUploadFailed", message: "Failed to upload blob to storage"})
    # end
  end

  defp get_content_type(conn) do
    case get_req_header(conn, "content-type") do
      [content_type | _] -> content_type
      [] -> "application/octet-stream"
    end
  end
end
