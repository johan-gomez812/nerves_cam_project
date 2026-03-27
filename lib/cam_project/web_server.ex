defmodule CamProject.WebServer do
  require Logger

  def child_spec(_opts) do
    port = 4000

    Logger.info("WebServer: starting on port #{port}")

    Plug.Cowboy.child_spec(
      scheme: :http,
      plug: CamProject.WebRouter,
      options: [port: port]
    )
  end
end

