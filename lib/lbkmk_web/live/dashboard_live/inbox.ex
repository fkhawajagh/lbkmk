defmodule LbkmkWeb.DashboardLive.Inbox do
  use LbkmkWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :sale_events, [])}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1>Inbox</h1>
      <p>Placeholder: sale events will appear here.</p>
    </div>
    """
  end
end
