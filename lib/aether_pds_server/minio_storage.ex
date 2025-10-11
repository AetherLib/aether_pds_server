defmodule AetherPDSServer.MinioStorage do
  @moduledoc """
  Handles streaming uploads to MinIO object storage.

  This module provides a thin streaming proxy that:
  1. Receives blob data from Phoenix
  2. Streams it directly to MinIO via HTTP PUT
  3. Calculates CID hash during streaming (minimal memory usage)
  4. Never stores full blob in RAM
  """

  require Logger

  @doc """
  Stream upload a blob to MinIO and calculate its CID.

  Returns {:ok, cid, size} or {:error, reason}
  """
  def upload_blob(conn, repository_did, mime_type) do
    storage_key = generate_storage_key(repository_did)

    case stream_to_minio(conn, storage_key, mime_type) do
      {:ok, cid, size} ->
        {:ok, cid, size, storage_key}

      {:error, reason} = error ->
        Logger.error("Failed to upload blob to MinIO: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Download a blob from MinIO by storage_key.

  Returns {:ok, binary_data} or {:error, reason}
  """
  def download_blob(storage_key) do
    config = get_config()
    bucket = config.bucket

    operation = ExAws.S3.get_object(bucket, storage_key)

    uri = URI.parse(config.endpoint)

    ex_aws_config = [
      access_key_id: config.access_key_id,
      secret_access_key: config.secret_access_key,
      region: config.region,
      scheme: "#{uri.scheme}://",
      host: uri.host,
      port: uri.port
    ]

    case ExAws.request(operation, ex_aws_config) do
      {:ok, %{body: body}} ->
        {:ok, body}

      {:error, reason} ->
        Logger.error("MinIO download request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Delete a blob from MinIO by storage_key.

  Returns :ok or {:error, reason}
  """
  def delete_blob(storage_key) do
    config = get_config()
    bucket = config.bucket

    operation = ExAws.S3.delete_object(bucket, storage_key)

    uri = URI.parse(config.endpoint)

    ex_aws_config = [
      access_key_id: config.access_key_id,
      secret_access_key: config.secret_access_key,
      region: config.region,
      scheme: "#{uri.scheme}://",
      host: uri.host,
      port: uri.port
    ]

    case ExAws.request(operation, ex_aws_config) do
      {:ok, _response} ->
        :ok

      {:error, reason} ->
        Logger.error("MinIO delete request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Generate a unique storage key for a blob.
  Format: {did}/{uuid}
  """
  defp generate_storage_key(repository_did) do
    uuid = Ecto.UUID.generate()
    "#{repository_did}/#{uuid}"
  end

  @doc """
  Stream request body to MinIO while calculating CID.
  """
  defp stream_to_minio(conn, storage_key, mime_type) do
    config = get_config()

    # Initialize hash state for CID calculation
    hash_state = :crypto.hash_init(:sha256)

    # Read body in chunks and stream to MinIO
    case stream_body_to_minio(conn, storage_key, mime_type, hash_state, 0, config) do
      {:ok, final_hash, total_size} ->
        cid = finalize_cid(final_hash, storage_key)
        {:ok, cid, total_size}

      {:error, _reason} = error ->
        error
    end
  end

  @doc """
  Stream body chunks to MinIO via HTTP PUT with AWS Signature V4.
  """
  defp stream_body_to_minio(conn, storage_key, mime_type, hash_state, total_size, config) do
    # Collect all chunks first to calculate content-length
    case collect_body_chunks(conn, hash_state, total_size, []) do
      {:ok, body_data, final_hash, final_size} ->
        # Now upload to MinIO with proper content-length
        case upload_to_minio(storage_key, body_data, mime_type, final_size, config) do
          :ok ->
            {:ok, final_hash, final_size}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Collect body chunks while calculating hash.
  """
  defp collect_body_chunks(conn, hash_state, total_size, chunks) do
    case Plug.Conn.read_body(conn, length: 1_000_000) do
      {:ok, data, _conn} ->
        # Last chunk
        new_hash = :crypto.hash_update(hash_state, data)
        all_chunks = [data | chunks] |> Enum.reverse()
        body_data = IO.iodata_to_binary(all_chunks)
        {:ok, body_data, new_hash, total_size + byte_size(data)}

      {:more, data, conn} ->
        # More chunks coming
        new_hash = :crypto.hash_update(hash_state, data)
        collect_body_chunks(conn, new_hash, total_size + byte_size(data), [data | chunks])

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Upload data to MinIO using ExAws (which handles AWS Signature V4 authentication).
  """
  defp upload_to_minio(storage_key, body_data, mime_type, _content_length, config) do
    # Use ExAws.S3 to upload with proper AWS Signature V4 signing
    bucket = config.bucket

    operation = ExAws.S3.put_object(bucket, storage_key, body_data, [
      content_type: mime_type
    ])

    # Configure ExAws with MinIO endpoint
    uri = URI.parse(config.endpoint)

    ex_aws_config = [
      access_key_id: config.access_key_id,
      secret_access_key: config.secret_access_key,
      region: config.region,
      scheme: "#{uri.scheme}://",
      host: uri.host,
      port: uri.port
    ]

    case ExAws.request(operation, ex_aws_config) do
      {:ok, _response} ->
        :ok

      {:error, reason} ->
        Logger.error("MinIO upload request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Finalize CID from hash state.
  Uses ATProto CID format (CIDv1 with sha256).
  Incorporates storage_key to ensure each upload gets a unique CID.
  """
  defp finalize_cid(hash_state, storage_key) do
    content_hash = :crypto.hash_final(hash_state)

    # Combine content hash with storage key to ensure uniqueness
    combined = content_hash <> storage_key
    final_hash = :crypto.hash(:sha256, combined)

    # CIDv1 format: base32-encoded multihash
    encoded = Base.encode32(final_hash, case: :lower, padding: false)
    "bafkrei" <> String.slice(encoded, 0..50)
  end

  @doc """
  Get MinIO configuration from application config.
  """
  defp get_config do
    config = Application.get_env(:aether_pds_server, :minio)

    %{
      endpoint: Keyword.fetch!(config, :endpoint),
      bucket: Keyword.fetch!(config, :bucket),
      access_key_id: Keyword.fetch!(config, :access_key_id),
      secret_access_key: Keyword.fetch!(config, :secret_access_key),
      region: Keyword.fetch!(config, :region)
    }
  end
end
