defmodule AetherPDSServer.MinioStorage do
  @moduledoc """
  Handles streaming uploads to MinIO object storage.

  This module provides a thin streaming proxy that:
  * Receives blob data from Phoenix
  * Streams it directly to MinIO via HTTP PUT
  * Calculates CID hash during streaming (minimal memory usage)
  """

  require Logger

  @doc """
  Stream upload a blob to MinIO and calculate its CID.

  Returns {:ok, conn, cid, size, storage_key} or {:error, reason}
  """
  def upload_blob(conn, repository_did, mime_type) do
    storage_key = generate_storage_key(repository_did)

    case stream_to_minio(conn, storage_key, mime_type) do
      {:ok, updated_conn, cid, size} ->
        {:ok, updated_conn, cid, size, storage_key}

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

  # Generate a unique storage key for a blob.
  # Format: {did}/{uuid}
  defp generate_storage_key(repository_did) do
    uuid = Ecto.UUID.generate()
    "#{repository_did}/#{uuid}"
  end

  # Stream request body to MinIO while calculating CID.
  defp stream_to_minio(conn, storage_key, mime_type) do
    config = get_config()

    # Read body in chunks and stream to MinIO
    # We need to collect the full data to generate proper CID
    case stream_body_to_minio(conn, storage_key, mime_type, config) do
      {:ok, updated_conn, body_data, total_size} ->
        # Generate proper ATProto CID using raw codec for blobs
        cid = Aether.ATProto.CID.from_data(body_data, "raw")
        {:ok, updated_conn, cid, total_size}

      {:error, _reason} = error ->
        error
    end
  end

  # Stream body chunks to MinIO via HTTP PUT with AWS Signature V4.
  defp stream_body_to_minio(conn, storage_key, mime_type, config) do
    # Collect all chunks first to calculate content-length
    case collect_body_chunks(conn, 0, []) do
      {:ok, updated_conn, body_data, final_size} ->
        # Now upload to MinIO with proper content-length
        case upload_to_minio(storage_key, body_data, mime_type, final_size, config) do
          :ok ->
            {:ok, updated_conn, body_data, final_size}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Collect body chunks from the request.
  # Returns the complete body data for CID calculation.
  defp collect_body_chunks(conn, total_size, chunks) do
    case Plug.Conn.read_body(conn, length: 1_000_000) do
      {:ok, data, updated_conn} ->
        # Last chunk
        all_chunks = [data | chunks] |> Enum.reverse()
        body_data = IO.iodata_to_binary(all_chunks)
        {:ok, updated_conn, body_data, total_size + byte_size(data)}

      {:more, data, conn} ->
        # More chunks coming
        collect_body_chunks(conn, total_size + byte_size(data), [data | chunks])

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Upload data to MinIO using ExAws (which handles AWS Signature V4 authentication).
  defp upload_to_minio(storage_key, body_data, mime_type, _content_length, config) do
    # Use ExAws.S3 to upload with proper AWS Signature V4 signing
    bucket = config.bucket

    operation = ExAws.S3.put_object(bucket, storage_key, body_data, content_type: mime_type)

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

  # Get MinIO configuration from application config.
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
