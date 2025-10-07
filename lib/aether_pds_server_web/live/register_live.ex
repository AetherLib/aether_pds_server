defmodule AetherPDSServerWeb.RegisterLive do
  use AetherPDSServerWeb, :live_view

  alias AetherPDSServer.Accounts

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:form, to_form(%{"handle" => "", "email" => "", "password" => ""}))
     |> assign(:error, nil)
     |> assign(:success, false)}
  end

  def handle_event("validate", %{"register" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params))}
  end

  def handle_event("register", %{"register" => params}, socket) do
    attrs = %{
      handle: params["handle"],
      email: params["email"],
      password: params["password"]
    }

    case Accounts.create_account(attrs) do
      {:ok, account} ->
        {:noreply,
         socket
         |> assign(:success, true)
         |> assign(:account, account)
         |> assign(:error, nil)}

      {:error, %Ecto.Changeset{} = changeset} ->
        errors = format_changeset_errors(changeset)

        {:noreply,
         socket
         |> assign(:error, errors)
         |> assign(:success, false)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:error, "Failed to create account: #{inspect(reason)}")
         |> assign(:success, false)}
    end
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, errors} ->
      "#{field}: #{Enum.join(errors, ", ")}"
    end)
    |> Enum.join("; ")
  end

  def render(assigns) do
    ~H"""
    <div class="container">
      <div class="register-box">
        <h1>Create Account</h1>
        <p class="subtitle">Join the AT Protocol network</p>

        <%= if @success do %>
          <div class="success-message">
            <h2>✓ Account Created Successfully!</h2>
            <p>Your DID: <code><%= @account.did %></code></p>
            <p>Handle: <strong>@<%= @account.handle %></strong></p>
            <div class="actions">
              <.link navigate={~p"/oauth/login"} class="button primary">
                Go to Login
              </.link>
              <.link navigate="/" class="button">
                Home
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
            phx-submit="register"
            class="register-form"
          >
            <div class="form-group">
              <label for="handle">Handle</label>
              <div class="input-wrapper">
                <span class="input-prefix">@</span>
                <input
                  type="text"
                  name="register[handle]"
                  id="handle"
                  value={@form.params["handle"]}
                  placeholder="username.bsky.social"
                  required
                  autocomplete="username"
                />
              </div>
              <small class="help-text">Your unique username on the network</small>
            </div>

            <div class="form-group">
              <label for="email">Email</label>
              <input
                type="email"
                name="register[email]"
                id="email"
                value={@form.params["email"]}
                placeholder="you@example.com"
                required
                autocomplete="email"
              />
              <small class="help-text">Used for account recovery</small>
            </div>

            <div class="form-group">
              <label for="password">Password</label>
              <input
                type="password"
                name="register[password]"
                id="password"
                value={@form.params["password"]}
                placeholder="••••••••••"
                required
                autocomplete="new-password"
                minlength="8"
              />
              <small class="help-text">At least 8 characters</small>
            </div>

            <button type="submit" class="button primary full-width">
              Create Account
            </button>
          </.form>

          <div class="footer-links">
            <p>
              Already have an account?
              <.link navigate={~p"/oauth/login"} class="link">
                Sign in
              </.link>
            </p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
