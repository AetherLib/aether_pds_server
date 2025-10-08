defmodule AetherPDSServer.DIDDocumentTest do
  use ExUnit.Case, async: true

  alias AetherPDSServer.DIDDocument

  describe "generate/3" do
    test "generates a valid DID document" do
      account = %{did: "did:plc:abc123", handle: "alice.example.com"}
      pds_endpoint = "https://pds.example.com"

      doc = DIDDocument.generate(account, pds_endpoint)

      assert doc["id"] == "did:plc:abc123"
      assert doc["alsoKnownAs"] == ["at://alice.example.com"]
      assert is_list(doc["service"])
      assert length(doc["service"]) == 1

      [service] = doc["service"]
      assert service["type"] == "AtprotoPersonalDataServer"
      assert service["serviceEndpoint"] == "https://pds.example.com"
    end

    test "includes custom also_known_as entries" do
      account = %{did: "did:plc:abc123", handle: "alice.example.com"}
      pds_endpoint = "https://pds.example.com"
      opts = [also_known_as: ["https://alice.example.com"]]

      doc = DIDDocument.generate(account, pds_endpoint, opts)

      assert doc["alsoKnownAs"] == [
               "at://alice.example.com",
               "https://alice.example.com"
             ]
    end

    test "includes verification methods when provided" do
      account = %{did: "did:plc:abc123", handle: "alice.example.com"}
      pds_endpoint = "https://pds.example.com"

      verification_methods = [
        %{
          "id" => "#key-1",
          "type" => "EcdsaSecp256k1VerificationKey2019",
          "controller" => "did:plc:abc123"
        }
      ]

      opts = [verification_methods: verification_methods]
      doc = DIDDocument.generate(account, pds_endpoint, opts)

      assert doc["verificationMethod"] == verification_methods
    end

    test "does not include verification methods when empty" do
      account = %{did: "did:plc:abc123", handle: "alice.example.com"}
      pds_endpoint = "https://pds.example.com"

      doc = DIDDocument.generate(account, pds_endpoint)

      refute Map.has_key?(doc, "verificationMethod")
    end
  end

  describe "validate/1" do
    test "validates a correct DID document" do
      did_doc = %{
        "id" => "did:plc:abc123",
        "service" => [
          %{
            "type" => "AtprotoPersonalDataServer",
            "serviceEndpoint" => "https://pds.example.com"
          }
        ]
      }

      assert {:ok, ^did_doc} = DIDDocument.validate(did_doc)
    end

    test "returns error for missing required fields" do
      did_doc = %{
        "id" => "did:plc:abc123"
        # Missing service
      }

      assert {:error, {:missing_fields, ["service"]}} = DIDDocument.validate(did_doc)
    end

    test "returns error for missing id field" do
      did_doc = %{
        "service" => []
      }

      assert {:error, {:missing_fields, ["id"]}} = DIDDocument.validate(did_doc)
    end

    test "returns error for empty service array" do
      did_doc = %{
        "id" => "did:plc:abc123",
        "service" => []
      }

      assert {:error, :no_service_endpoints} = DIDDocument.validate(did_doc)
    end

    test "returns error for non-map input" do
      assert {:error, :invalid_did_document} = DIDDocument.validate("not a map")
      assert {:error, :invalid_did_document} = DIDDocument.validate(nil)
    end
  end

  describe "generate_for_web/3" do
    test "generates a did:web document" do
      account = %{did: "did:plc:abc123", handle: "alice.example.com"}
      pds_endpoint = "https://pds.example.com"
      domain = "example.com"

      doc = DIDDocument.generate_for_web(account, pds_endpoint, domain)

      assert doc["id"] == "did:web:example.com"
      assert "at://alice.example.com" in doc["alsoKnownAs"]
      assert "did:plc:abc123" in doc["alsoKnownAs"]

      [service] = doc["service"]
      assert service["type"] == "AtprotoPersonalDataServer"
      assert service["serviceEndpoint"] == "https://pds.example.com"
    end
  end

  describe "get_pds_endpoint/1" do
    test "extracts PDS endpoint from DID document" do
      did_doc = %{
        "service" => [
          %{
            "type" => "AtprotoPersonalDataServer",
            "serviceEndpoint" => "https://pds.example.com"
          }
        ]
      }

      assert {:ok, "https://pds.example.com"} = DIDDocument.get_pds_endpoint(did_doc)
    end

    test "returns error when no PDS endpoint found" do
      did_doc = %{
        "service" => []
      }

      assert {:error, :pds_endpoint_not_found} = DIDDocument.get_pds_endpoint(did_doc)
    end
  end
end
