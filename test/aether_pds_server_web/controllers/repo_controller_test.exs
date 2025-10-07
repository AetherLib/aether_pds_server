defmodule AetherPDSServerWeb.RepoControllerTest do
  use AetherPDSServerWeb.ConnCase


  setup %{conn: conn} do
    # Create account and get token
    params = %{
      "handle" => "repouser.test",
      "email" => "repo@example.com",
      "password" => "testpassword"
    }

    conn = post(conn, ~p"/xrpc/com.atproto.server.createAccount", params)
    json = json_response(conn, 200)

    %{
      access_token: json["accessJwt"],
      did: json["did"]
    }
  end

  describe "GET /xrpc/com.atproto.repo.describeRepo" do
    test "returns repository description", %{conn: conn, did: did} do
      conn = get(conn, ~p"/xrpc/com.atproto.repo.describeRepo?repo=#{did}")

      assert json = json_response(conn, 200)
      assert json["did"] == did
      assert json["collections"]
      assert is_list(json["collections"])
    end

    test "returns error for non-existent repository", %{conn: conn} do
      conn = get(conn, ~p"/xrpc/com.atproto.repo.describeRepo?repo=did:plc:nonexistent")

      assert json = json_response(conn, 404)
      assert json["error"] == "RepoNotFound"
    end
  end

  describe "POST /xrpc/com.atproto.repo.createRecord" do
    test "creates record with valid attributes", %{access_token: token, did: did} do
      params = %{
        "repo" => did,
        "collection" => "app.bsky.feed.post",
        "record" => %{
          "text" => "Hello, world!",
          "createdAt" => "2024-01-01T00:00:00.000Z"
        }
      }

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/xrpc/com.atproto.repo.createRecord", params)

      assert json = json_response(conn, 200)
      assert json["uri"]
      assert String.starts_with?(json["uri"], "at://")
      assert json["cid"]
      assert json["commit"]["cid"]
      assert json["commit"]["rev"]
    end

    test "creates record with custom rkey", %{access_token: token, did: did} do
      params = %{
        "repo" => did,
        "collection" => "app.bsky.feed.post",
        "rkey" => "custom123",
        "record" => %{
          "text" => "Custom rkey post"
        }
      }

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/xrpc/com.atproto.repo.createRecord", params)

      assert json = json_response(conn, 200)
      assert String.contains?(json["uri"], "custom123")
    end

    test "returns error for duplicate record", %{access_token: token, did: did} do
      params = %{
        "repo" => did,
        "collection" => "app.bsky.feed.post",
        "rkey" => "duplicate",
        "record" => %{"text" => "First"}
      }

      # Create first record
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> post(~p"/xrpc/com.atproto.repo.createRecord", params)

      # Try to create duplicate
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/xrpc/com.atproto.repo.createRecord", params)

      assert json = json_response(conn, 409)
      assert json["error"] == "RecordAlreadyExists"
    end

    test "returns error without authentication", %{conn: conn, did: did} do
      params = %{
        "repo" => did,
        "collection" => "app.bsky.feed.post",
        "record" => %{"text" => "Unauthorized"}
      }

      conn = post(conn, ~p"/xrpc/com.atproto.repo.createRecord", params)

      assert json = json_response(conn, 401)
      assert json["error"]
    end
  end

  describe "GET /xrpc/com.atproto.repo.getRecord" do
    setup %{access_token: token, did: did} do
      # Create a record first
      params = %{
        "repo" => did,
        "collection" => "app.bsky.feed.post",
        "rkey" => "testrkey",
        "record" => %{"text" => "Test record"}
      }

      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> post(~p"/xrpc/com.atproto.repo.createRecord", params)

      %{rkey: "testrkey"}
    end

    test "returns record when found", %{conn: conn, did: did, rkey: rkey} do
      conn =
        get(
          conn,
          ~p"/xrpc/com.atproto.repo.getRecord?repo=#{did}&collection=app.bsky.feed.post&rkey=#{rkey}"
        )

      assert json = json_response(conn, 200)
      assert json["uri"]
      assert json["cid"]
      assert json["value"]["text"] == "Test record"
    end

    test "returns error when not found", %{conn: conn, did: did} do
      conn =
        get(
          conn,
          ~p"/xrpc/com.atproto.repo.getRecord?repo=#{did}&collection=app.bsky.feed.post&rkey=nonexistent"
        )

      assert json = json_response(conn, 404)
      assert json["error"] == "RecordNotFound"
    end
  end

  describe "POST /xrpc/com.atproto.repo.putRecord" do
    test "creates new record when not exists", %{access_token: token, did: did} do
      params = %{
        "repo" => did,
        "collection" => "app.bsky.feed.post",
        "rkey" => "newrecord",
        "record" => %{"text" => "New record"}
      }

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/xrpc/com.atproto.repo.putRecord", params)

      assert json = json_response(conn, 200)
      assert json["uri"]
      assert json["cid"]
    end

    test "updates existing record", %{access_token: token, did: did} do
      rkey = "updaterecord"

      # Create initial record
      create_params = %{
        "repo" => did,
        "collection" => "app.bsky.feed.post",
        "rkey" => rkey,
        "record" => %{"text" => "Original"}
      }

      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> post(~p"/xrpc/com.atproto.repo.createRecord", create_params)

      # Update record
      update_params = %{
        "repo" => did,
        "collection" => "app.bsky.feed.post",
        "rkey" => rkey,
        "record" => %{"text" => "Updated"}
      }

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/xrpc/com.atproto.repo.putRecord", update_params)

      assert json = json_response(conn, 200)
      assert json["cid"]

      # Verify update
      get_conn =
        build_conn()
        |> get(
          ~p"/xrpc/com.atproto.repo.getRecord?repo=#{did}&collection=app.bsky.feed.post&rkey=#{rkey}"
        )

      get_json = json_response(get_conn, 200)
      assert get_json["value"]["text"] == "Updated"
    end
  end

  describe "POST /xrpc/com.atproto.repo.deleteRecord" do
    setup %{access_token: token, did: did} do
      # Create a record to delete
      params = %{
        "repo" => did,
        "collection" => "app.bsky.feed.post",
        "rkey" => "deleteme",
        "record" => %{"text" => "Delete this"}
      }

      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> post(~p"/xrpc/com.atproto.repo.createRecord", params)

      %{rkey: "deleteme"}
    end

    test "deletes existing record", %{access_token: token, did: did, rkey: rkey} do
      params = %{
        "repo" => did,
        "collection" => "app.bsky.feed.post",
        "rkey" => rkey
      }

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/xrpc/com.atproto.repo.deleteRecord", params)

      assert json = json_response(conn, 200)
      assert json["commit"]["cid"]
      assert json["commit"]["rev"]

      # Verify deletion
      get_conn =
        build_conn()
        |> get(
          ~p"/xrpc/com.atproto.repo.getRecord?repo=#{did}&collection=app.bsky.feed.post&rkey=#{rkey}"
        )

      assert json_response(get_conn, 404)
    end

    test "returns error for non-existent record", %{access_token: token, did: did} do
      params = %{
        "repo" => did,
        "collection" => "app.bsky.feed.post",
        "rkey" => "nonexistent"
      }

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/xrpc/com.atproto.repo.deleteRecord", params)

      assert json = json_response(conn, 404)
      assert json["error"] == "RecordNotFound"
    end
  end

  describe "GET /xrpc/com.atproto.repo.listRecords" do
    setup %{access_token: token, did: did} do
      # Create multiple records
      for i <- 1..5 do
        params = %{
          "repo" => did,
          "collection" => "app.bsky.feed.post",
          "record" => %{"text" => "Post #{i}"}
        }

        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/xrpc/com.atproto.repo.createRecord", params)
      end

      :ok
    end

    test "lists records in collection", %{conn: conn, did: did} do
      conn =
        get(conn, ~p"/xrpc/com.atproto.repo.listRecords?repo=#{did}&collection=app.bsky.feed.post")

      assert json = json_response(conn, 200)
      assert json["records"]
      assert length(json["records"]) == 5
      assert Enum.all?(json["records"], &String.contains?(&1["uri"], "app.bsky.feed.post"))
    end

    test "respects limit parameter", %{conn: conn, did: did} do
      conn =
        get(
          conn,
          ~p"/xrpc/com.atproto.repo.listRecords?repo=#{did}&collection=app.bsky.feed.post&limit=2"
        )

      assert json = json_response(conn, 200)
      assert length(json["records"]) == 2
      assert json["cursor"]
    end

    test "handles pagination with cursor", %{conn: conn, did: did} do
      # Get first page
      conn1 =
        get(
          conn,
          ~p"/xrpc/com.atproto.repo.listRecords?repo=#{did}&collection=app.bsky.feed.post&limit=2"
        )

      json1 = json_response(conn1, 200)
      cursor = json1["cursor"]

      # Get second page
      conn2 =
        get(
          conn,
          ~p"/xrpc/com.atproto.repo.listRecords?repo=#{did}&collection=app.bsky.feed.post&limit=2&cursor=#{cursor}"
        )

      json2 = json_response(conn2, 200)

      # Should have different records
      uris1 = Enum.map(json1["records"], & &1["uri"])
      uris2 = Enum.map(json2["records"], & &1["uri"])
      assert uris1 != uris2
    end
  end
end
