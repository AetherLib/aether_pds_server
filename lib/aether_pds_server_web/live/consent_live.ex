defmodule AetherPDSServerWeb.ConsentLive do
  use AetherPDSServerWeb, :live_view

  alias AetherPDSServer.{Accounts, OAuth}

  def mount(params, _session, socket) do
    client_id = params["client_id"]
    redirect_uri = params["redirect_uri"]
    state = params["state"]
    code_challenge = params["code_challenge"]
    scope = params["scope"] || "atproto"
    did = params["did"]

    # Validate client
    client_info =
      case OAuth.validate_client(client_id, redirect_uri) do
        {:ok, info} -> info
        {:error, _} -> nil
      end

    # Get account info
    account = if did, do: Accounts.get_account_by_did(did), else: nil

    {:ok,
     socket
     |> assign(:client_id, client_id)
     |> assign(:redirect_uri, redirect_uri)
     |> assign(:state, state)
     |> assign(:code_challenge, code_challenge)
     |> assign(:scope, scope)
     |> assign(:did, did)
     |> assign(:account, account)
     |> assign(:client_info, client_info)
     |> assign(:error, nil)}
  end

  def handle_event("authorize", _params, socket) do
    # Create authorization code
    case OAuth.create_authorization_code(
           socket.assigns.did,
           socket.assigns.client_id,
           socket.assigns.redirect_uri,
           socket.assigns.code_challenge,
           socket.assigns.scope
         ) do
      {:ok, code} ->
        # Build redirect URL with authorization code
        redirect_url =
          build_redirect_url(
            socket.assigns.redirect_uri,
            code,
            socket.assigns.state
          )

        {:noreply, redirect(socket, external: redirect_url)}

      {:error, reason} ->
        {:noreply,
         assign(socket, :error, "Failed to create authorization code: #{inspect(reason)}")}
    end
  end

  def handle_event("deny", _params, socket) do
    # Build redirect URL with error
    redirect_url =
      build_error_redirect_url(
        socket.assigns.redirect_uri,
        "access_denied",
        "User denied authorization",
        socket.assigns.state
      )

    {:noreply, redirect(socket, external: redirect_url)}
  end

  defp build_redirect_url(base_uri, code, state) do
    uri = URI.parse(base_uri)
    query = URI.decode_query(uri.query || "")

    query =
      query
      |> Map.put("code", code)
      |> Map.put("state", state || "")

    %{uri | query: URI.encode_query(query)}
    |> URI.to_string()
  end

  defp build_error_redirect_url(base_uri, error, error_description, state) do
    uri = URI.parse(base_uri)
    query = URI.decode_query(uri.query || "")

    query =
      query
      |> Map.put("error", error)
      |> Map.put("error_description", error_description)
      |> Map.put("state", state || "")

    %{uri | query: URI.encode_query(query)}
    |> URI.to_string()
  end

  def render(assigns) do
    ~H"""
    <div class="container">
      <div class="consent-box">
        <h1>Authorize Application</h1>

        <%= if @error do %>
          <div class="error-message">
            <strong>Error:</strong> <%= @error %>
          </div>
        <% end %>

        <%= if @account && @client_info do %>
          <div class="consent-info">
            <div class="client-details">
              <h2>Application Details</h2>
              <div class="detail-item">
                <label>Application:</label>
                <strong><%= @client_info.name %></strong>
              </div>
              <div class="detail-item">
                <label>Client ID:</label>
                <code><%= @client_id %></code>
              </div>
              <div class="detail-item">
                <label>Redirect URI:</label>
                <code><%= @redirect_uri %></code>
              </div>
            </div>

            <div class="user-details">
              <h2>Signing in as</h2>
              <div class="user-info">
                <strong>@<%= @account.handle %></strong>
                <br />
                <small><%= @account.did %></small>
              </div>
            </div>

            <div class="permissions">
              <h2>Requested Permissions</h2>
              <ul class="permission-list">
                <li>
                  <span class="permission-icon">✓</span>
                  Read your profile information
                </li>
                <li>
                  <span class="permission-icon">✓</span>
                  Create and manage posts
                </li>
                <li>
                  <span class="permission-icon">✓</span>
                  Access your repository data
                </li>
                <%= if @scope && String.contains?(@scope, "write") do %>
                  <li>
                    <span class="permission-icon">⚠</span>
                    <strong>Write access to your account</strong>
                  </li>
                <% end %>
              </ul>
            </div>

            <div class="consent-actions">
              <button phx-click="authorize" class="button primary">
                Authorize Application
              </button>
              <button phx-click="deny" class="button secondary">
                Deny
              </button>
            </div>

            <div class="security-notice">
              <p>
                <small>
                  🔒 Only authorize applications you trust. This application will be able to
                  access your account with the permissions listed above.
                </small>
              </p>
            </div>
          </div>
        <% else %>
          <div class="error-message">
            <p>Invalid authorization request. Please try again.</p>
            <.link navigate={~p"/oauth/login"} class="button">
              Back to Login
            </.link>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
