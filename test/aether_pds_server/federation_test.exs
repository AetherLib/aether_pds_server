defmodule AetherPDSServer.FederationTest do
  use ExUnit.Case, async: true

  alias AetherPDSServer.Federation

  describe "discover_pds/1" do
    test "returns error for non-existent handle" do
      # Without mocking, this will fail to resolve
      assert {:error, _} = Federation.discover_pds("nonexistent.invalid")
    end

    test "returns error for non-existent DID" do
      # Without mocking, this will fail to resolve
      assert {:error, _} = Federation.discover_pds("did:plc:nonexistent123")
    end

    test "returns error for unsupported DID method" do
      # This should fail at the DID resolver level
      assert {:error, :unsupported_did_method} = Federation.discover_pds("did:key:abc123")
    end
  end

  describe "fetch_remote_record/3" do
    test "returns error when PDS discovery fails" do
      # Without mocking, this will fail at PDS discovery
      result = Federation.fetch_remote_record("did:plc:nonexistent", "app.bsky.feed.post", "abc")
      assert {:error, _} = result
    end
  end

  describe "fetch_remote_records/3" do
    test "returns error when PDS discovery fails" do
      # Without mocking, this will fail at PDS discovery
      result = Federation.fetch_remote_records("did:plc:nonexistent", "app.bsky.feed.post")
      assert {:error, _} = result
    end

    test "accepts limit option" do
      # Just verify the function accepts the option
      result = Federation.fetch_remote_records("did:plc:nonexistent", "app.bsky.feed.post", limit: 10)
      assert {:error, _} = result
    end

    test "accepts cursor option" do
      # Just verify the function accepts the option
      result = Federation.fetch_remote_records("did:plc:nonexistent", "app.bsky.feed.post", cursor: "abc")
      assert {:error, _} = result
    end
  end

  describe "verify_remote_repository/1" do
    test "returns error when PDS discovery fails" do
      # Without mocking, this will fail at PDS discovery
      assert {:error, _} = Federation.verify_remote_repository("did:plc:nonexistent")
    end
  end
end
