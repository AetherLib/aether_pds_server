# lib/aether_pds_server/token.ex
defmodule AetherPDSServer.Token do
  @moduledoc """
  JWT token generation and verification for authentication.
  """

  @doc """
  Generate an access token (JWT) for a DID
  """
  def generate_access_token(did) do
    signer = get_signer()

    claims = %{
      "sub" => did,
      "scope" => "atproto",
      "iss" => AetherPDSServerWeb.Endpoint.url(),
      "iat" => Joken.current_time(),
      # 1 hour
      "exp" => Joken.current_time() + 3600
    }

    # Use empty config (no validators)
    Joken.generate_and_sign(%{}, claims, signer)
  end

  @doc """
  Generate a refresh token (JWT) for a DID
  """
  def generate_refresh_token(did) do
    signer = get_signer()

    claims = %{
      "sub" => did,
      "scope" => "refresh",
      "iss" => AetherPDSServerWeb.Endpoint.url(),
      "iat" => Joken.current_time(),
      # 30 days
      "exp" => Joken.current_time() + 60 * 60 * 24 * 30
    }

    # Use empty config (no validators)
    Joken.generate_and_sign(%{}, claims, signer)
  end

  @doc """
  Verify and decode a token
  """
  def verify_token(token) do
    signer = get_signer()

    # Use empty config (no validators) - just verify signature
    case Joken.verify_and_validate(%{}, token, signer) do
      {:ok, claims} -> {:ok, claims}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_signer do
    Joken.Signer.create("HS256", get_secret())
  end

  defp get_secret do
    Application.get_env(:aether_pds_server, :token_secret) ||
      raise "TOKEN_SECRET not configured! Add it to your config."
  end
end
