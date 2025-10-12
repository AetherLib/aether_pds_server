defmodule AetherPDSServerWeb.HomeLive do
  use AetherPDSServerWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="container">
      <div class="home-hero">
        <h1>Aether PDS Server</h1>
        <p class="hero-subtitle">
          A personal data server on the AT Protocol network built in elixir and phoenix
        </p>

        <div class="hero-actions">
          <.link navigate={~p"/register"} class="button primary large">
            Create Account
          </.link>
          <.link navigate={~p"/oauth/login"} class="button large">
            Sign In
          </.link>
        </div>
      </div>
    </div>
    """
  end
end
