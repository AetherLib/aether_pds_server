# lib/aether_pds_server_web/controllers/blob_controller.ex
defmodule AetherPDSServerWeb.ComATProto.BlobController do
  use AetherPDSServerWeb, :controller

  alias AetherPDSServer.Repositories

  @doc """
  POST /xrpc/com.atproto.repo.uploadBlob

  Upload a blob (image, video, etc.)
  """
  def upload_blob(conn, _params) do
    did = conn.assigns[:current_did]

    # Read raw body
    {:ok, body, conn} = Plug.Conn.read_body(conn)

    if byte_size(body) == 0 do
      conn
      |> put_status(:bad_request)
      |> json(%{error: "InvalidRequest", message: "No blob data provided"})
    else
      # Generate CID for blob
      blob_cid = generate_blob_cid(body)
      mime_type = get_content_type(conn)

      blob_attrs = %{
        repository_did: did,
        cid: blob_cid,
        mime_type: mime_type,
        size: byte_size(body),
        data: body
      }

      case Repositories.create_blob(blob_attrs) do
        {:ok, _blob} ->
          response = %{
            blob: %{
              "$type" => "blob",
              ref: %{
                "$link" => blob_cid
              },
              mimeType: mime_type,
              size: byte_size(body)
            }
          }

          json(conn, response)

        {:error, changeset} ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "BlobUploadFailed", message: inspect(changeset)})
      end
    end
  end

  defp generate_blob_cid(data) do
    hash = :crypto.hash(:sha256, data)
    encoded = Base.encode32(hash, case: :lower, padding: false)
    "bafkrei" <> String.slice(encoded, 0..50)
  end

  defp get_content_type(conn) do
    case get_req_header(conn, "content-type") do
      [content_type | _] -> content_type
      [] -> "application/octet-stream"
    end
  end
end
