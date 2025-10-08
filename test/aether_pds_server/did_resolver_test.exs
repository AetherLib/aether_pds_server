defmodule AetherPDSServer.DIDResolverTest do
  use ExUnit.Case, async: true

  alias AetherPDSServer.DIDResolver

  describe "resolve_did/1" do
    test "returns error for unsupported DID methods" do
      assert {:error, :unsupported_did_method} = DIDResolver.resolve_did("did:key:abc123")
      assert {:error, :unsupported_did_method} = DIDResolver.resolve_did("did:peer:abc123")
    end

    test "returns error for invalid DID format" do
      assert {:error, :unsupported_did_method} = DIDResolver.resolve_did("not-a-did")
      assert {:error, :unsupported_did_method} = DIDResolver.resolve_did("")
    end
  end

  describe "get_pds_endpoint/1" do
    test "extracts PDS endpoint from valid DID document" do
      did_doc = %{
        "id" => "did:plc:abc123",
        "service" => [
          %{
            "type" => "AtprotoPersonalDataServer",
            "serviceEndpoint" => "https://pds.example.com"
          }
        ]
      }

      assert {:ok, "https://pds.example.com"} = DIDResolver.get_pds_endpoint(did_doc)
    end

    test "returns error when no PDS service found" do
      did_doc = %{
        "id" => "did:plc:abc123",
        "service" => [
          %{
            "type" => "SomeOtherService",
            "serviceEndpoint" => "https://other.example.com"
          }
        ]
      }

      assert {:error, :pds_endpoint_not_found} = DIDResolver.get_pds_endpoint(did_doc)
    end

    test "returns error when service array is empty" do
      did_doc = %{
        "id" => "did:plc:abc123",
        "service" => []
      }

      assert {:error, :pds_endpoint_not_found} = DIDResolver.get_pds_endpoint(did_doc)
    end

    test "returns error when service field is missing" do
      did_doc = %{
        "id" => "did:plc:abc123"
      }

      assert {:error, :pds_endpoint_not_found} = DIDResolver.get_pds_endpoint(did_doc)
    end

    test "returns error for invalid DID document" do
      assert {:error, :invalid_did_document} = DIDResolver.get_pds_endpoint(nil)
      assert {:error, :invalid_did_document} = DIDResolver.get_pds_endpoint("not a map")
    end
  end

  describe "resolve_handle_to_pds/1" do
    # Note: These would require mocking HTTP requests in a real test
    # For now, we test that the function exists and handles errors

    test "returns error for non-existent handle" do
      # This will fail because we can't resolve non-existent handles
      assert {:error, _} = DIDResolver.resolve_handle_to_pds("nonexistent.invalid")
    end
  end
end
