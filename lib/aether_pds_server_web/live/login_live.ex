defmodule AetherPDSServerWeb.LoginLive do
  use AetherPDSServerWeb, :live_view

  alias AetherPDSServer.Accounts

  def mount(params, _session, socket) do
    # Get OAuth parameters from query string if present
    client_id = params["client_id"]
    redirect_uri = params["redirect_uri"]
    state = params["state"]
    code_challenge = params["code_challenge"]
    scope = params["scope"] || "atproto"

    {:ok,
     socket
     |> assign(:form, to_form(%{"identifier" => "", "password" => ""}))
     |> assign(:error, nil)
     |> assign(:client_id, client_id)
     |> assign(:redirect_uri, redirect_uri)
     |> assign(:state, state)
     |> assign(:code_challenge, code_challenge)
     |> assign(:scope, scope)
     |> assign(:is_oauth_flow, !is_nil(client_id))}
  end

  def handle_event("validate", %{"login" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params))}
  end

  def handle_event("login", %{"login" => params}, socket) do
    case Accounts.authenticate(params["identifier"], params["password"]) do
      {:ok, account} ->
        if socket.assigns.is_oauth_flow do
          # OAuth flow - redirect to consent page
          {:noreply,
           socket
           |> put_flash(:info, "Login successful")
           |> redirect(
             to:
               ~p"/oauth/authorize/consent?client_id=#{socket.assigns.client_id}&redirect_uri=#{socket.assigns.redirect_uri}&state=#{socket.assigns.state}&code_challenge=#{socket.assigns.code_challenge}&scope=#{socket.assigns.scope}&did=#{account.did}"
           )}
        else
          # Direct login - create session tokens
          {:ok, access_token} = Accounts.create_access_token(account.did)
          {:ok, refresh_token} = Accounts.create_refresh_token(account.did)

          {:noreply,
           socket
           |> assign(:success, true)
           |> assign(:account, account)
           |> assign(:access_token, access_token)
           |> assign(:refresh_token, refresh_token)
           |> assign(:error, nil)}
        end

      {:error, :invalid_credentials} ->
        {:noreply,
         socket
         |> assign(:error, "Invalid username or password")
         |> assign(:form, to_form(params))}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="container">
      <div class="login-box">
        <h1>Sign In</h1>
        <%= if @is_oauth_flow do %>
          <div class="oauth-info">
            <p class="oauth-label">Signing in for:</p>
            <p class="oauth-client"><%= @client_id %></p>
          </div>
        <% else %>
          <p class="subtitle">Access your AT Protocol account</p>
        <% end %>

        <%= if assigns[:success] do %>
          <div class="success-message">
            <h2>✓ Login Successful!</h2>
            <p>Welcome back, <strong>@<%= @account.handle %></strong></p>

            <div class="token-display">
              <div class="token-item">
                <label>Access Token:</label>
                <code class="token"><%= String.slice(@access_token, 0..50) %>...</code>
              </div>
              <div class="token-item">
                <label>Refresh Token:</label>
                <code class="token"><%= String.slice(@refresh_token, 0..50) %>...</code>
              </div>
            </div>

            <div class="actions">
              <.link navigate="/" class="button primary">
                Continue
              </.link>
            </div>
          </div>
        <% else %>
          <%= if @error do %>
            <div class="error-message">
              <strong>Error:</strong> <%= @error %>
            </div>
          <% end %>

          <.form
            for={@form}
            phx-change="validate"
            phx-submit="login"
            class="login-form"
          >
            <div class="form-group">
              <label for="identifier">Handle or Email</label>
              <input
                type="text"
                name="login[identifier]"
                id="identifier"
                value={@form.params["identifier"]}
                placeholder="username.bsky.social or email"
                required
                autocomplete="username"
              />
            </div>

            <div class="form-group">
              <label for="password">Password</label>
              <input
                type="password"
                name="login[password]"
                id="password"
                value={@form.params["password"]}
                placeholder="••••••••••"
                required
                autocomplete="current-password"
              />
            </div>

            <button type="submit" class="button primary full-width">
              Sign In
            </button>
          </.form>

          <div class="footer-links">
            <p>
              Don't have an account?
              <.link navigate={~p"/register"} class="link">
                Create one
              </.link>
            </p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
