defmodule AetherPDSServerWeb.OAuthHTML do
  @moduledoc """
  OAuth HTML templates for login and consent pages.
  """
  use AetherPDSServerWeb, :html

  embed_templates "oauth_html/*"
end
