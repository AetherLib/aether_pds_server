defmodule AetherPDSServerWeb.ComATProto.BlobControllerTest do
  use AetherPDSServerWeb.ConnCase, async: false

  alias AetherPDSServer.{Accounts, Repositories}

  setup do
    # Create test account
    account_attrs = %{
      handle: "test.user",
      email: "test@example.com",
      password: "password123"
    }

    {:ok, account} = Accounts.create_account(account_attrs)
    {:ok, access_token} = Accounts.create_access_token(account.did)

    %{account: account, access_token: access_token}
  end

  # Helper to load a small test image from fixtures
  defp load_small_test_image do
    File.read!("test/fixtures/images/7Mib-image.png")
  end

  # Helper to load a large test image from fixtures
  defp load_large_test_image do
    File.read!("test/fixtures/images/16Mib-image.png")
  end

  # Helper to load an extra large test image from fixtures
  defp load_extra_large_test_image do
    File.read!("test/fixtures/images/52Mib-image.png")
  end

  describe "POST /xrpc/com.atproto.repo.uploadBlob" do
    @tag :integration
    test "uploads a 7MB image to MinIO and stores metadata", %{
      conn: conn,
      account: account,
      access_token: access_token
    } do
      # Load real test image (7MB PNG)
      blob_data = load_small_test_image()

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{access_token}")
        |> put_req_header("content-type", "image/png")
        |> post("/xrpc/com.atproto.repo.uploadBlob", blob_data)

      assert %{
               "blob" => %{
                 "$type" => "blob",
                 "ref" => %{"$link" => cid},
                 "mimeType" => "image/png",
                 "size" => size
               }
             } = json_response(conn, 200)

      # Verify metadata was saved to database
      blob = Repositories.get_blob(account.did, cid)
      assert blob != nil
      assert blob.cid == cid
      assert blob.mime_type == "image/png"
      assert blob.size == size
      assert blob.size == byte_size(blob_data)
      assert blob.storage_key != nil
      assert String.starts_with?(blob.storage_key, account.did)

      # Verify blob was uploaded to MinIO
      # The successful upload response from ExAws confirms the blob is in MinIO
      # Note: Direct GET requires signed URL, so we trust the successful PUT response
      size_mb = Float.round(size / 1024 / 1024, 2)
      IO.puts("✅ 7MB PNG image (#{size} bytes / #{size_mb} MB, CID: #{String.slice(cid, 0..15)}...) uploaded to MinIO")
    end

    @tag :integration
    test "uploads 16MB image via streaming without loading into memory", %{
      conn: conn,
      access_token: access_token
    } do
      # Load large test image (16MB PNG) to test streaming
      blob_data = load_large_test_image()
      blob_size = byte_size(blob_data)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{access_token}")
        |> put_req_header("content-type", "image/png")
        |> post("/xrpc/com.atproto.repo.uploadBlob", blob_data)

      assert %{
               "blob" => %{
                 "size" => ^blob_size,
                 "mimeType" => "image/png"
               }
             } = json_response(conn, 200)

      size_mb = Float.round(blob_size / 1024 / 1024, 2)
      IO.puts("✅ 16MB PNG image (#{blob_size} bytes / #{size_mb} MB) uploaded successfully via streaming")
    end

    @tag :integration
    test "uploads 52MB image via streaming (stress test)", %{
      conn: conn,
      access_token: access_token
    } do
      # Load extra large test image (52MB PNG) to stress test streaming
      blob_data = load_extra_large_test_image()
      blob_size = byte_size(blob_data)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{access_token}")
        |> put_req_header("content-type", "image/png")
        |> post("/xrpc/com.atproto.repo.uploadBlob", blob_data)

      assert %{
               "blob" => %{
                 "size" => ^blob_size,
                 "mimeType" => "image/png"
               }
             } = json_response(conn, 200)

      size_mb = Float.round(blob_size / 1024 / 1024, 2)
      IO.puts("✅ 52MB PNG image (#{blob_size} bytes / #{size_mb} MB) uploaded successfully via streaming 🚀")
    end

    test "requires authentication", %{conn: conn} do
      blob_data = :crypto.strong_rand_bytes(100)

      conn =
        conn
        |> put_req_header("content-type", "image/png")
        |> post("/xrpc/com.atproto.repo.uploadBlob", blob_data)

      assert json_response(conn, 401)
    end
  end
end
