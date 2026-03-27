defmodule CamProject.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {CamProject.DetectionStore, []},
      {CamProject.Recorder, []},
      {CamProject.WebServer, []},
      {CamProject.LiveStream, []}
    ]

    opts = [strategy: :one_for_one, name: CamProject.Supervisor]

    Task.start(fn -> CamProject.CameraProbe.check() end)
    Task.start(fn -> CamProject.CameraStream.verify_stream() end)

    Supervisor.start_link(children, opts)
  end
end
