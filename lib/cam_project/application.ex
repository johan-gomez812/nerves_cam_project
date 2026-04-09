defmodule CamProject.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {CamProject.DetectionStore, []},
      {CamProject.Recorder, []},
      {CamProject.WebServer, []},
      {CamProject.Pipeline, []}
    ]

    opts = [strategy: :one_for_one, name: CamProject.Supervisor]

    Task.start(fn -> CamProject.CameraProbe.check() end)
    Task.start(fn -> CamProject.CameraStream.verify_stream() end)
    Task.start(fn -> start_tailscale() end)

    Supervisor.start_link(children, opts)
  end

  defp start_tailscale do
    System.cmd("mkdir", ["-p", "/data/tailscale"])
    Task.start(fn ->
      System.cmd("tailscaled", [
        "--state=/data/tailscale/tailscaled.state",
        "--tun=userspace-networking"
      ])
    end)
    :timer.sleep(3000)
    System.cmd("tailscale", [
      "up",
      "--authkey=tskey-auth-krMzDM3ce211CNTRL-WPyuRVWvziDKQdrASPWKiDf95gA5weVM"
    ], stderr_to_stdout: true)
  end
end
