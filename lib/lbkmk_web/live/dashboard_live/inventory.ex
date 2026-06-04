defmodule LbkmkWeb.DashboardLive.Inventory do
  use LbkmkWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :items, [])}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1>Inventory</h1>
      <p>Placeholder: inventory items will appear here.</p>
    </div>
    """
  end
end
