defmodule AetherPDSServerWeb.ServerControllerTest do
  use AetherPDSServerWeb.ConnCase

  alias AetherPDSServer.Accounts

  describe "GET /xrpc/com.atproto.server.describeServer" do
    test "returns server metadata", %{conn: conn} do
      conn = get(conn, ~p"/xrpc/com.atproto.server.describeServer")

      assert json = json_response(conn, 200)
      assert json["availableUserDomains"]
      assert json["inviteCodeRequired"] == false
      assert json["links"]
    end
  end

  describe "POST /xrpc/com.atproto.server.createAccount" do
    test "creates account with valid attributes", %{conn: conn} do
      params = %{
        "handle" => "newuser.test",
        "email" => "newuser@example.com",
        "password" => "securepassword123"
      }

      conn = post(conn, ~p"/xrpc/com.atproto.server.createAccount", params)

      assert json = json_response(conn, 200)
      assert json["handle"] == "newuser.test"
      assert json["did"]
      assert String.starts_with?(json["did"], "did:plc:")
      assert json["accessJwt"]
      assert json["refreshJwt"]
    end

    test "returns error with missing required fields", %{conn: conn} do
      params = %{"handle" => "newuser.test"}

      conn = post(conn, ~p"/xrpc/com.atproto.server.createAccount", params)

      assert json = json_response(conn, 400)
      assert json["error"]
    end

    test "returns error with duplicate handle", %{conn: conn} do
      params = %{
        "handle" => "duplicate.test",
        "email" => "user1@example.com",
        "password" => "password123"
      }

      # Create first account
      post(conn, ~p"/xrpc/com.atproto.server.createAccount", params)

      # Try to create second account with same handle
      params2 = %{
        "handle" => "duplicate.test",
        "email" => "user2@example.com",
        "password" => "password456"
      }

      conn = post(conn, ~p"/xrpc/com.atproto.server.createAccount", params2)

      assert json = json_response(conn, 400)
      assert json["error"]
    end
  end

  describe "POST /xrpc/com.atproto.server.createSession" do
    setup %{conn: conn} do
      params = %{
        "handle" => "loginuser.test",
        "email" => "login@example.com",
        "password" => "testpassword"
      }

      conn = post(conn, ~p"/xrpc/com.atproto.server.createAccount", params)
      json = json_response(conn, 200)

      %{did: json["did"]}
    end

    test "logs in with valid handle and password", %{conn: conn} do
      params = %{
        "identifier" => "loginuser.test",
        "password" => "testpassword"
      }

      conn = post(conn, ~p"/xrpc/com.atproto.server.createSession", params)

      assert json = json_response(conn, 200)
      assert json["handle"] == "loginuser.test"
      assert json["did"]
      assert json["accessJwt"]
      assert json["refreshJwt"]
    end

    test "logs in with valid email and password", %{conn: conn} do
      params = %{
        "identifier" => "login@example.com",
        "password" => "testpassword"
      }

      conn = post(conn, ~p"/xrpc/com.atproto.server.createSession", params)

      assert json = json_response(conn, 200)
      assert json["handle"] == "loginuser.test"
      assert json["did"]
    end

    test "returns error with invalid password", %{conn: conn} do
      params = %{
        "identifier" => "loginuser.test",
        "password" => "wrongpassword"
      }

      conn = post(conn, ~p"/xrpc/com.atproto.server.createSession", params)

      assert json = json_response(conn, 401)
      assert json["error"] == "AuthenticationFailed"
    end

    test "returns error with non-existent user", %{conn: conn} do
      params = %{
        "identifier" => "nonexistent.test",
        "password" => "password"
      }

      conn = post(conn, ~p"/xrpc/com.atproto.server.createSession", params)

      assert json = json_response(conn, 401)
      assert json["error"] == "AuthenticationFailed"
    end
  end

  describe "POST /xrpc/com.atproto.server.refreshSession" do
    setup %{conn: conn} do
      params = %{
        "handle" => "refreshuser.test",
        "email" => "refresh@example.com",
        "password" => "testpassword"
      }

      conn = post(conn, ~p"/xrpc/com.atproto.server.createAccount", params)
      json = json_response(conn, 200)

      %{refresh_token: json["refreshJwt"], did: json["did"]}
    end

    test "refreshes session with valid refresh token", %{conn: conn, refresh_token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/xrpc/com.atproto.server.refreshSession")

      assert json = json_response(conn, 200)
      assert json["accessJwt"]
      assert json["refreshJwt"]
      assert json["handle"] == "refreshuser.test"
      assert json["did"]
    end

    test "returns error with invalid refresh token", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer invalid_token")
        |> post(~p"/xrpc/com.atproto.server.refreshSession")

      assert json = json_response(conn, 401)
      assert json["error"] == "InvalidToken"
    end

    test "returns error without authorization header", %{conn: conn} do
      conn = post(conn, ~p"/xrpc/com.atproto.server.refreshSession")

      assert json = json_response(conn, 400)
      assert json["error"]
    end
  end

  describe "GET /xrpc/com.atproto.server.getSession" do
    setup %{conn: conn} do
      params = %{
        "handle" => "sessionuser.test",
        "email" => "session@example.com",
        "password" => "testpassword"
      }

      conn = post(conn, ~p"/xrpc/com.atproto.server.createAccount", params)
      json = json_response(conn, 200)

      %{access_token: json["accessJwt"], did: json["did"]}
    end

    test "returns session info with valid token", %{conn: conn, access_token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/xrpc/com.atproto.server.getSession")

      assert json = json_response(conn, 200)
      assert json["handle"] == "sessionuser.test"
      assert json["email"] == "session@example.com"
      assert json["did"]
    end

    test "returns error without authorization", %{conn: conn} do
      conn = get(conn, ~p"/xrpc/com.atproto.server.getSession")

      assert json = json_response(conn, 401)
      assert json["error"]
    end
  end

  describe "POST /xrpc/com.atproto.server.deleteSession" do
    setup %{conn: conn} do
      params = %{
        "handle" => "logoutuser.test",
        "email" => "logout@example.com",
        "password" => "testpassword"
      }

      conn = post(conn, ~p"/xrpc/com.atproto.server.createAccount", params)
      json = json_response(conn, 200)

      %{access_token: json["accessJwt"], did: json["did"]}
    end

    test "logs out successfully with valid token", %{conn: conn, access_token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/xrpc/com.atproto.server.deleteSession")

      assert json = json_response(conn, 200)
      assert json == %{}
    end

    test "returns error without authorization", %{conn: conn} do
      conn = post(conn, ~p"/xrpc/com.atproto.server.deleteSession")

      assert json = json_response(conn, 401)
      assert json["error"]
    end
  end
end
