defmodule LbkmkWeb.DashboardLive.Skus do
  use LbkmkWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :skus, [])}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1>Channel SKUs</h1>
      <p>Placeholder: SKU mappings will appear here.</p>
    </div>
    """
  end
end
