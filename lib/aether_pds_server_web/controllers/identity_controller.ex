# lib/aether_pds_server_web/controllers/identity_controller.ex
defmodule AetherPDSServerWeb.IdentityController do
  use AetherPDSServerWeb, :controller

  alias AetherPDSServer.Accounts

  @doc """
  GET /xrpc/com.atproto.identity.resolveHandle

  Resolve a handle to a DID
  """
  def resolve_handle(conn, %{"handle" => handle}) do
    case Accounts.get_account_by_handle(handle) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "HandleNotFound", message: "Handle not found"})

      account ->
        json(conn, %{did: account.did})
    end
  end
end
