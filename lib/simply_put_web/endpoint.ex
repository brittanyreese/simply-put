defmodule SimplyPutWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :simply_put

  @session_options [
    store: :cookie,
    key: "_simply_put_key",
    signing_salt: "sp_session_salt",
    same_site: "Lax"
  ]

  # No auth/session data is read inside any LiveView, so the socket
  # doesn't need connect_info: [session: ...] -- that mechanism requires
  # a session cookie to already exist, which a plain `fetch_session`
  # (no `put_session`) never sets, and LiveView rejects the mount as
  # "stale" when it's configured but comes back nil on connect.
  socket("/live", Phoenix.LiveView.Socket, websocket: true, longpoll: true)

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
