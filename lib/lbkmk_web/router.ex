defmodule LbkmkWeb.Router do
  use LbkmkWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {LbkmkWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", LbkmkWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/api/v1", LbkmkWeb.API do
    pipe_through :api

    post "/sale-events", SaleEventController, :create
    get "/sale-events", SaleEventController, :index
    post "/xero-write-result", XeroWriteResultController, :create
    post "/payouts", PayoutController, :create
  end

  scope "/", LbkmkWeb do
    pipe_through :browser

    live "/inbox", DashboardLive.Inbox
    live "/events/:id", DashboardLive.EventDetail
    live "/skus", DashboardLive.Skus
    live "/inventory", DashboardLive.Inventory
  end
end
