defmodule AetherPDSServer.DIDResolver do
  @moduledoc """
  Resolves AT Protocol handles and DIDs to DID documents.

  Supports:
  - Handle resolution via HTTPS well-known endpoints
  - Handle resolution via DNS TXT records
  - DID resolution for did:plc and did:web methods

  ## Examples

      iex> DIDResolver.resolve_handle("alice.bsky.social")
      {:ok, "did:plc:abc123..."}

      iex> DIDResolver.resolve_did("did:plc:abc123...")
      {:ok, %{"id" => "did:plc:abc123...", "service" => [...]}}

      iex> DIDResolver.get_pds_endpoint(did_doc)
      {:ok, "https://pds.example.com"}
  """

  require Logger

  @doc """
  Resolves a handle to a DID.

  Tries HTTPS well-known endpoint first, falls back to DNS TXT records.

  ## Examples

      iex> resolve_handle("alice.bsky.social")
      {:ok, "did:plc:abc123..."}
  """
  def resolve_handle(handle) do
    url = "https://#{handle}/.well-known/atproto-did"

    with {:ok, %{status: 200, body: did}} when is_binary(did) <- http_get(url),
         did <- String.trim(did) do
      Logger.debug("Resolved handle #{handle} via HTTPS: #{did}")
      {:ok, did}
    else
      _ -> resolve_handle_via_dns(handle)
    end
  end

  @doc """
  Resolves a DID to its DID document.

  Supports:
  - did:web (via local lookup or HTTPS .well-known/did.json)
  - did:plc (via plc.directory) - for external/legacy DIDs

  ## Examples

      iex> resolve_did("did:web:alice.aetherlib.org")
      {:ok, %{"id" => "did:web:alice.aetherlib.org", ...}}
  """
  def resolve_did("did:web:" <> domain) do
    # Try local resolution first for our own accounts
    case resolve_local_did_web(domain) do
      {:ok, did_doc} ->
        {:ok, did_doc}

      {:error, :not_local} ->
        # Fall back to HTTPS resolution for external DIDs
        url = "https://#{domain}/.well-known/did.json"

        case http_get(url) do
          {:ok, %{status: 200, body: did_doc}} when is_map(did_doc) ->
            Logger.debug("Resolved did:web document for #{domain}")
            {:ok, did_doc}

          {:ok, %{status: status}} ->
            Logger.error("Failed to resolve did:web #{domain}: HTTP #{status}")
            {:error, :did_resolution_failed}

          {:error, reason} ->
            Logger.error("Failed to resolve did:web #{domain}: #{inspect(reason)}")
            {:error, :did_resolution_failed}
        end
    end
  end

  def resolve_did("did:plc:" <> _ = did) do
    # Legacy support for did:plc (external DIDs only)
    url = "https://plc.directory/#{did}"

    case http_get(url) do
      {:ok, %{status: 200, body: did_doc}} when is_map(did_doc) ->
        Logger.debug("Resolved DID document for #{did}")
        {:ok, did_doc}

      {:ok, %{status: status}} ->
        Logger.error("Failed to resolve DID #{did}: HTTP #{status}")
        {:error, :did_resolution_failed}

      {:error, reason} ->
        Logger.error("Failed to resolve DID #{did}: #{inspect(reason)}")
        {:error, :did_resolution_failed}
    end
  end

  def resolve_did(_), do: {:error, :unsupported_did_method}

  @doc """
  Extracts PDS (Personal Data Server) endpoint from a DID document.

  Looks for a service entry with type "AtprotoPersonalDataServer".

  ## Examples

      iex> did_doc = %{"service" => [%{"type" => "AtprotoPersonalDataServer", "serviceEndpoint" => "https://pds.example.com"}]}
      iex> get_pds_endpoint(did_doc)
      {:ok, "https://pds.example.com"}
  """
  def get_pds_endpoint(did_doc) when is_map(did_doc) do
    Logger.debug("Extracting PDS endpoint from DID document")

    did_doc
    |> Map.get("service", [])
    |> Enum.find(&(&1["type"] == "AtprotoPersonalDataServer"))
    |> case do
      %{"serviceEndpoint" => endpoint} when is_binary(endpoint) ->
        {:ok, endpoint}

      _ ->
        Logger.warning("No PDS endpoint found in DID document")
        {:error, :pds_endpoint_not_found}
    end
  end

  def get_pds_endpoint(_), do: {:error, :invalid_did_document}

  @doc """
  Resolves a handle all the way to a PDS endpoint.

  This is a convenience function that chains:
  handle → DID → DID document → PDS endpoint

  ## Examples

      iex> resolve_handle_to_pds("alice.bsky.social")
      {:ok, "https://pds.example.com"}
  """
  def resolve_handle_to_pds(handle) do
    with {:ok, did} <- resolve_handle(handle),
         {:ok, did_doc} <- resolve_did(did),
         {:ok, pds_endpoint} <- get_pds_endpoint(did_doc) do
      {:ok, pds_endpoint}
    end
  end

  # Private functions

  defp resolve_local_did_web(domain) do
    # Check if this is one of our local accounts
    alias AetherPDSServer.Accounts
    alias AetherPDSServer.DIDDocument

    case Accounts.get_account_by_handle(domain) do
      nil ->
        {:error, :not_local}

      account ->
        # Generate DID document locally without HTTP request
        pds_endpoint = get_local_pds_endpoint()

        did_doc = %{
          "@context" => [
            "https://www.w3.org/ns/did/v1",
            "https://w3id.org/security/suites/secp256k1-2019/v1"
          ],
          "id" => account.did,
          "alsoKnownAs" => ["at://#{account.handle}"],
          "service" => [
            %{
              "id" => "#atproto_pds",
              "type" => "AtprotoPersonalDataServer",
              "serviceEndpoint" => pds_endpoint
            }
          ]
        }

        Logger.debug("Resolved local did:web for #{domain}")
        {:ok, did_doc}
    end
  end

  defp get_local_pds_endpoint do
    case Application.get_env(:aether_pds_server, :pds_endpoint) do
      nil ->
        endpoint_config = Application.get_env(:aether_pds_server, AetherPDSServerWeb.Endpoint)
        url_config = Keyword.get(endpoint_config, :url, [])
        host = Keyword.get(url_config, :host, "localhost")
        port = Keyword.get(url_config, :port, 4000)
        scheme = if Keyword.get(url_config, :scheme) == "https", do: "https", else: "http"

        port_suffix =
          cond do
            scheme == "https" and port == 443 -> ""
            scheme == "http" and port == 80 -> ""
            true -> ":#{port}"
          end

        "#{scheme}://#{host}#{port_suffix}"

      endpoint ->
        endpoint
    end
  end

  defp resolve_handle_via_dns(handle) do
    dns_name = ~c"_atproto.#{handle}"
    Logger.debug("Resolving handle via DNS TXT record: #{dns_name}")

    with txt_records when txt_records != [] <- safe_dns_lookup(dns_name),
         did when not is_nil(did) <- parse_did_from_txt_records(txt_records) do
      Logger.debug("Resolved handle #{handle} via DNS: #{did}")
      {:ok, did}
    else
      _ ->
        Logger.debug("No valid DID found in DNS for #{handle}")
        {:error, :handle_resolution_failed}
    end
  end

  defp safe_dns_lookup(dns_name) do
    :inet_res.lookup(dns_name, :in, :txt)
  catch
    :exit, reason ->
      Logger.error("DNS lookup failed: #{inspect(reason)}")
      []
  end

  defp parse_did_from_txt_records(txt_records) do
    Logger.debug("Parsing DID from DNS TXT records: #{inspect(txt_records)}")

    Enum.find_value(txt_records, fn record ->
      txt_value =
        record
        |> List.flatten()
        |> List.to_string()
        |> String.trim()

      Logger.debug("Parsed TXT value: #{txt_value}")

      case txt_value do
        "did=" <> did -> did
        "did:" <> _ = did -> did
        _ -> nil
      end
    end)
  end

  defp http_get(url) do
    base_opts = Application.get_env(:aether_pds_server, :req_options, [])

    case Req.get(url, base_opts) do
      {:ok, %{body: body} = response} when is_binary(body) ->
        case Jason.decode(body) do
          {:ok, decoded} -> {:ok, %{response | body: decoded}}
          {:error, _} -> {:ok, response}
        end

      other ->
        other
    end
  end
end
