defmodule AetherPDSServer.DIDDocument do
  @moduledoc """
  Generates and manages AT Protocol DID documents.

  A DID document contains:
  - id: The DID itself
  - alsoKnownAs: Array of alternate identifiers (handles)
  - verificationMethod: Cryptographic keys for verification
  - service: Service endpoints (PDS, relay, etc.)

  ## Examples

      iex> account = %{did: "did:plc:abc123", handle: "alice.example.com"}
      iex> DIDDocument.generate(account, "https://pds.example.com")
      %{
        "@context" => ["https://www.w3.org/ns/did/v1"],
        "id" => "did:plc:abc123",
        "alsoKnownAs" => ["at://alice.example.com"],
        "service" => [...]
      }
  """

  @doc """
  Generates a DID document for an account.

  ## Parameters
  - account: Account struct with :did and :handle
  - pds_endpoint: URL of this PDS server
  - opts: Optional parameters
    - :verification_methods - Custom verification methods
    - :also_known_as - Additional identifiers
  """
  def generate(account, pds_endpoint, opts \\ []) do
    also_known_as = build_also_known_as(account, opts)
    verification_methods = build_verification_methods(account, opts)
    services = build_services(pds_endpoint)

    doc = %{
      "@context" => [
        "https://www.w3.org/ns/did/v1",
        "https://w3id.org/security/suites/secp256k1-2019/v1"
      ],
      "id" => account.did,
      "alsoKnownAs" => also_known_as,
      "service" => services
    }

    if verification_methods != [] do
      Map.put(doc, "verificationMethod", verification_methods)
    else
      doc
    end
  end

  @doc """
  Extracts the PDS endpoint from a DID document.

  This is a convenience wrapper around DIDResolver.get_pds_endpoint/1
  """
  def get_pds_endpoint(did_doc) do
    AetherPDSServer.DIDResolver.get_pds_endpoint(did_doc)
  end

  @doc """
  Validates a DID document structure.

  Returns {:ok, did_doc} if valid, {:error, reason} otherwise.
  """
  def validate(did_doc) when is_map(did_doc) do
    with :ok <- validate_required_fields(did_doc),
         :ok <- validate_service_endpoints(did_doc) do
      {:ok, did_doc}
    end
  end

  def validate(_), do: {:error, :invalid_did_document}

  # Private functions

  defp build_also_known_as(account, opts) do
    base = ["at://#{account.handle}"]
    additional = Keyword.get(opts, :also_known_as, [])
    base ++ additional
  end

  defp build_verification_methods(_account, opts) do
    # For now, return custom verification methods from opts
    # In a full implementation, you'd generate signing keys here
    Keyword.get(opts, :verification_methods, [])
  end

  defp build_services(pds_endpoint) do
    [
      %{
        "id" => "#atproto_pds",
        "type" => "AtprotoPersonalDataServer",
        "serviceEndpoint" => pds_endpoint
      }
    ]
  end

  defp validate_required_fields(did_doc) do
    required = ["id", "service"]

    missing =
      Enum.filter(required, fn field ->
        not Map.has_key?(did_doc, field)
      end)

    if missing == [] do
      :ok
    else
      {:error, {:missing_fields, missing}}
    end
  end

  defp validate_service_endpoints(did_doc) do
    services = Map.get(did_doc, "service", [])

    if is_list(services) and length(services) > 0 do
      :ok
    else
      {:error, :no_service_endpoints}
    end
  end

  @doc """
  Generates a simple DID document for serving at /.well-known/did.json

  This supports did:web method where DIDs are resolved via HTTPS.
  """
  def generate_for_web(account, pds_endpoint, domain) do
    did = "did:web:#{domain}"

    %{
      "@context" => [
        "https://www.w3.org/ns/did/v1"
      ],
      "id" => did,
      "alsoKnownAs" => ["at://#{account.handle}", account.did],
      "service" => [
        %{
          "id" => "#atproto_pds",
          "type" => "AtprotoPersonalDataServer",
          "serviceEndpoint" => pds_endpoint
        }
      ]
    }
  end
end
