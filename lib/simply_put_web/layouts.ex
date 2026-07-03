defmodule SimplyPutWeb.Layouts do
  use Phoenix.Component

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
        <title>Simply Put</title>
        <style>
          body { font-family: system-ui, sans-serif; margin: 2rem; color: #1a1a1a; }
          table { border-collapse: collapse; width: 100%; margin-top: 1rem; }
          th, td { text-align: left; padding: 0.4rem 0.8rem; border-bottom: 1px solid #ddd; }
          .passed { color: #0a7a2f; font-weight: 600; }
          .held { color: #b3261e; font-weight: 600; }
          .summary { display: flex; gap: 2rem; margin: 1rem 0; }
          .summary strong { display: block; font-size: 1.4rem; }
          .histogram { display: flex; align-items: flex-end; gap: 4px; height: 120px; margin: 1rem 0; }
          .histogram .bar { display: flex; flex-direction: column-reverse; width: 32px; }
          .histogram .bar span { display: block; }
          .histogram .bar .held-part { background: #e3a8a2; }
          .histogram .bar .passed-part { background: #8fd0a5; }
          .histogram .label { font-size: 0.7rem; text-align: center; margin-top: 2px; }
        </style>
      </head>
      <body>
        {@inner_content}
        <script type="module">
          import {Socket} from "/vendor/phoenix.mjs";
          import {LiveSocket} from "/vendor/phoenix_live_view.esm.js";

          const csrfToken = document
            .querySelector("meta[name='csrf-token']")
            .getAttribute("content");
          const liveSocket = new LiveSocket("/live", Socket, {
            params: { _csrf_token: csrfToken }
          });
          liveSocket.connect();
          window.liveSocket = liveSocket;
        </script>
      </body>
    </html>
    """
  end
end
