defmodule SimplyPutWeb.Router do
  use Phoenix.Router

  import Phoenix.Controller, only: [put_root_layout: 2]
  import Phoenix.LiveView.Router
  import Plug.Conn

  pipeline :browser do
    plug(:fetch_session)
    plug(:put_root_layout, html: {SimplyPutWeb.Layouts, :root})
  end

  scope "/" do
    pipe_through(:browser)

    live("/runs", SimplyPutWeb.RunsLive)
  end
end
