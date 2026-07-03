defmodule SimplyPutWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :simply_put

  @session_options [
    store: :cookie,
    key: "_simply_put_key",
    signing_salt: "sp_session_salt",
    same_site: "Lax"
  ]

  socket("/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]
  )

  # Serve the pre-built LiveView client JS straight out of the hex
  # packages -- no npm, no esbuild, no asset pipeline.
  plug(Plug.Static,
    at: "/vendor",
    from: {:phoenix, "priv/static"},
    only: ~w(phoenix.mjs)
  )

  plug(Plug.Static,
    at: "/vendor",
    from: {:phoenix_live_view, "priv/static"},
    only: ~w(phoenix_live_view.esm.js)
  )

  plug(Plug.RequestId)
  plug(Plug.Session, @session_options)
  plug(SimplyPutWeb.Router)
end
