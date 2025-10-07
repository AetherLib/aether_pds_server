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
          Your personal data server on the AT Protocol network
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

      <div class="features">
        <h2>Features</h2>

        <div class="feature-grid">
          <div class="feature-card">
            <div class="feature-icon">🔐</div>
            <h3>Secure Authentication</h3>
            <p>OAuth 2.0 with DPoP for secure token-based authentication</p>
          </div>

          <div class="feature-card">
            <div class="feature-icon">🌐</div>
            <h3>AT Protocol Compatible</h3>
            <p>Full support for the AT Protocol specification and federation</p>
          </div>

          <div class="feature-card">
            <div class="feature-icon">📦</div>
            <h3>Repository Management</h3>
            <p>Store and sync your data with content-addressed repositories</p>
          </div>

          <div class="feature-card">
            <div class="feature-icon">🔄</div>
            <h3>Sync Protocol</h3>
            <p>Export and sync repositories using CAR files</p>
          </div>
        </div>
      </div>

      <div class="api-info">
        <h2>API Endpoints</h2>
        <div class="endpoint-list">
          <div class="endpoint">
            <code>POST /xrpc/com.atproto.server.createAccount</code>
            <span>Create a new account</span>
          </div>
          <div class="endpoint">
            <code>POST /xrpc/com.atproto.server.createSession</code>
            <span>Login and get session tokens</span>
          </div>
          <div class="endpoint">
            <code>POST /xrpc/com.atproto.repo.createRecord</code>
            <span>Create a new record</span>
          </div>
          <div class="endpoint">
            <code>GET /xrpc/com.atproto.sync.getRepo</code>
            <span>Export repository as CAR file</span>
          </div>
        </div>

        <div class="api-links">
          <a href="/dev/dashboard" class="link">LiveDashboard →</a>
          <a href="/_health" class="link">Health Check →</a>
        </div>
      </div>
    </div>
    """
  end
end
