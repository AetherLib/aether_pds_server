defmodule AetherPDSServerWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.
  """
  use Phoenix.Component

  @doc """
  Renders flash notices.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id}>
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
    </div>
    """
  end

  @doc """
  Renders a single flash notice.
  """
  attr :flash, :map, required: true
  attr :kind, :atom, required: true

  def flash(assigns) do
    ~H"""
    <%= if Phoenix.Flash.get(@flash, @kind) do %>
      <div
        class={"flash flash-#{@kind}"}
        role="alert"
        phx-click="lv:clear-flash"
        phx-value-key={@kind}
      >
        <p><%= Phoenix.Flash.get(@flash, @kind) %></p>
      </div>
    <% end %>
    """
  end
end
