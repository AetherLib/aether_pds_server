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

  describe "GET /xrpc/com.atproto.sync.getBlob" do
    @tag :integration
    test "retrieves a blob from MinIO", %{
      conn: conn,
      account: account,
      access_token: access_token
    } do
      # First upload a blob
      blob_data = load_small_test_image()

      upload_conn =
        conn
        |> put_req_header("authorization", "Bearer #{access_token}")
        |> put_req_header("content-type", "image/png")
        |> post("/xrpc/com.atproto.repo.uploadBlob", blob_data)

      assert %{
               "blob" => %{
                 "ref" => %{"$link" => cid}
               }
             } = json_response(upload_conn, 200)

      # Now retrieve the blob
      download_conn = get(conn, "/xrpc/com.atproto.sync.getBlob?did=#{account.did}&cid=#{cid}")

      assert download_conn.status == 200
      [content_type | _] = get_resp_header(download_conn, "content-type")
      assert String.starts_with?(content_type, "image/png")
      downloaded_data = download_conn.resp_body
      assert downloaded_data == blob_data
      assert byte_size(downloaded_data) == byte_size(blob_data)
    end

    test "returns 404 for non-existent blob", %{conn: conn, account: account} do
      conn = get(conn, "/xrpc/com.atproto.sync.getBlob?did=#{account.did}&cid=bafkreifake")

      assert json_response(conn, 404) == %{
               "error" => "BlobNotFound",
               "message" => "Blob not found"
             }
    end
  end

  describe "Blob cleanup" do
    @tag :integration
    test "cleanup_unreferenced_blob deletes from MinIO when no references", %{
      conn: conn,
      account: account,
      access_token: access_token
    } do
      # Upload a blob
      blob_data = load_small_test_image()

      upload_conn =
        conn
        |> put_req_header("authorization", "Bearer #{access_token}")
        |> put_req_header("content-type", "image/png")
        |> post("/xrpc/com.atproto.repo.uploadBlob", blob_data)

      assert %{
               "blob" => %{
                 "ref" => %{"$link" => cid}
               }
             } = json_response(upload_conn, 200)

      # Verify blob exists in database
      blob = Repositories.get_blob(account.did, cid)
      assert blob != nil

      # Verify blob can be downloaded
      download_conn = get(conn, "/xrpc/com.atproto.sync.getBlob?did=#{account.did}&cid=#{cid}")
      assert download_conn.status == 200

      # Cleanup the blob (no references, so it should be deleted)
      assert {:ok, :deleted} = Repositories.cleanup_unreferenced_blob(cid)

      # Verify blob is deleted from database
      assert Repositories.get_blob(account.did, cid) == nil

      # Verify blob cannot be downloaded anymore
      download_conn2 = get(conn, "/xrpc/com.atproto.sync.getBlob?did=#{account.did}&cid=#{cid}")
      assert json_response(download_conn2, 404)
    end

    @tag :integration
    test "cleanup_unreferenced_blob keeps blob when referenced", %{
      conn: conn,
      account: account,
      access_token: access_token
    } do
      # Upload a blob
      blob_data = load_small_test_image()

      upload_conn =
        conn
        |> put_req_header("authorization", "Bearer #{access_token}")
        |> put_req_header("content-type", "image/png")
        |> post("/xrpc/com.atproto.repo.uploadBlob", blob_data)

      assert %{
               "blob" => %{
                 "ref" => %{"$link" => cid}
               }
             } = json_response(upload_conn, 200)

      # Create a reference to the blob
      {:ok, _ref} =
        Repositories.create_blob_ref(%{
          blob_cid: cid,
          repository_did: account.did,
          record_uri: "at://#{account.did}/app.bsky.feed.post/test123"
        })

      # Try to cleanup - should not delete because it's referenced
      assert {:ok, :still_referenced} = Repositories.cleanup_unreferenced_blob(cid)

      # Verify blob still exists
      assert Repositories.get_blob(account.did, cid) != nil

      # Verify blob can still be downloaded
      download_conn = get(conn, "/xrpc/com.atproto.sync.getBlob?did=#{account.did}&cid=#{cid}")
      assert download_conn.status == 200
    end
  end
end
