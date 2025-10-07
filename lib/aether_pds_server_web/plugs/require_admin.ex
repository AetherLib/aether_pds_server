defmodule AetherPDSServerWeb.Plugs.RequireAdmin do
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    did = conn.assigns[:current_did]

    if is_admin?(did) do
      conn
    else
      conn
      |> put_status(:forbidden)
      |> json(%{error: "Forbidden", message: "Admin privileges required"})
      |> halt()
    end
  end

  defp is_admin?(did) do
    # TODO: Check if DID has admin privileges
    # For now, check config
    admin_dids = Application.get_env(:aether_pds_server, :admin_dids, [])
    did in admin_dids
  end
end
