defmodule LbkmkWeb.DashboardLive.EventDetail do
  use LbkmkWeb, :live_view

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok, assign(socket, :event_id, id)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1>Event Detail</h1>
      <p>Placeholder: details for event {@event_id}.</p>
    </div>
    """
  end
end
